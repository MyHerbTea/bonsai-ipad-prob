import fs from "node:fs/promises";
import path from "node:path";
import OpenAI from "openai";

function arg(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  return fallback;
}

const baseURL = arg("--base-url", "http://192.168.0.103:8080/v1");
const apiKey = arg("--api-key");
const model = arg("--model", "bonsai-2-27b-local");
const outDir = arg("--out-dir", "D:\\apple\\re_output\\rc1252-js-sdk-probe");

if (!apiKey) {
  throw new Error("--api-key is required");
}

await fs.mkdir(outDir, { recursive: true });

const client = new OpenAI({
  baseURL,
  apiKey,
  maxRetries: 0,
  timeout: 120000,
});

const summary = {
  schema_version: 1,
  base_url: baseURL,
  model,
  checks: [],
  result: "FAIL",
};

const models = await client.models.list();
if (!models.data.some((item) => item.id === model)) {
  throw new Error(`model not found: ${model}`);
}
summary.checks.push("models_list=PASS");

const normal = await client.chat.completions.create({
  model,
  messages: [
    { role: "system", content: "Reply concisely." },
    { role: "user", content: "Reply exactly: JS_SDK_OK" },
  ],
  max_completion_tokens: 64,
  temperature: 0,
  top_p: 1,
});
if (!normal.choices?.[0]?.message?.content) {
  throw new Error("non-stream content is empty");
}
summary.checks.push("chat_non_stream=PASS");
await fs.writeFile(
  path.join(outDir, "02_non_stream.json"),
  JSON.stringify(normal, null, 2),
  "utf8",
);

const history = await client.chat.completions.create({
  model,
  messages: [
    { role: "system", content: "Use the supplied conversation history." },
    { role: "user", content: "Remember this code: ORCHID-JS61." },
    { role: "assistant", content: "I will remember ORCHID-JS61." },
    { role: "user", content: "What code did I give you? Reply with the code only." },
  ],
  max_completion_tokens: 48,
  temperature: 0,
});
if (!history.choices?.[0]?.message?.content?.includes("ORCHID-JS61")) {
  throw new Error("multi-turn history check failed");
}
summary.checks.push("multi_turn=PASS");

const toolNone = await client.chat.completions.create({
  model,
  messages: [{ role: "user", content: "Reply exactly: TOOL_NONE_OK" }],
  tools: [
    {
      type: "function",
      function: {
        name: "dummy",
        description: "Compatibility-only dummy function",
        parameters: { type: "object", properties: {} },
      },
    },
  ],
  tool_choice: "none",
  max_completion_tokens: 48,
});
if (!toolNone.choices?.[0]?.message?.content) {
  throw new Error("tool_choice=none returned empty content");
}
summary.checks.push("tool_choice_none=PASS");

const stream = await client.chat.completions.create({
  model,
  messages: [{ role: "user", content: "Reply exactly: JS_STREAM_OK" }],
  max_completion_tokens: 48,
  temperature: 0,
  stream: true,
  stream_options: { include_usage: true },
});

let streamText = "";
let usageSeen = false;
for await (const chunk of stream) {
  if (chunk.usage) usageSeen = true;
  const delta = chunk.choices?.[0]?.delta?.content;
  if (delta) streamText += delta;
}
if (!streamText.trim()) {
  throw new Error("streamed assistant content is empty");
}
if (!usageSeen) {
  throw new Error("stream usage chunk was not observed");
}
summary.checks.push("streaming=PASS");
summary.stream_text = streamText;

summary.result = "PASS";
await fs.writeFile(
  path.join(outDir, "SUMMARY.json"),
  JSON.stringify(summary, null, 2),
  "utf8",
);

console.log(JSON.stringify(summary, null, 2));
