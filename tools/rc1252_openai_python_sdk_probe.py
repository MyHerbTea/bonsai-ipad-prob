import argparse
import json
from pathlib import Path

from openai import OpenAI


def write_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="RC1.25.2 OpenAI Python SDK compatibility probe")
    parser.add_argument("--base-url", default="http://192.168.0.103:8080/v1")
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model", default="bonsai-2-27b-local")
    parser.add_argument(
        "--out-dir",
        default=r"D:\apple\re_output\rc1252-python-sdk-probe",
    )
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    client = OpenAI(
        base_url=args.base_url,
        api_key=args.api_key,
        timeout=120.0,
        max_retries=0,
    )

    summary = {
        "schema_version": 1,
        "base_url": args.base_url,
        "model": args.model,
        "checks": [],
        "result": "FAIL",
    }

    # 1. Models discovery
    models = client.models.list()
    model_ids = [item.id for item in models.data]
    assert args.model in model_ids, f"model not found: {args.model}"
    summary["checks"].append("models_list=PASS")

    # 2. Plain non-stream chat
    response = client.chat.completions.create(
        model=args.model,
        messages=[
            {"role": "system", "content": "Reply concisely."},
            {"role": "user", "content": "Reply exactly: PYTHON_SDK_OK"},
        ],
        max_completion_tokens=64,
        temperature=0,
        top_p=1,
    )
    text = response.choices[0].message.content or ""
    assert text.strip(), "non-stream content is empty"
    summary["checks"].append("chat_non_stream=PASS")
    write_json(
        out_dir / "02_non_stream.json",
        response.model_dump(mode="json"),
    )

    # 3. Multi-turn history
    response = client.chat.completions.create(
        model=args.model,
        messages=[
            {"role": "system", "content": "Use the supplied conversation history."},
            {"role": "user", "content": "Remember this code: ORCHID-PY61."},
            {"role": "assistant", "content": "I will remember ORCHID-PY61."},
            {"role": "user", "content": "What code did I give you? Reply with the code only."},
        ],
        max_completion_tokens=48,
        temperature=0,
    )
    text = response.choices[0].message.content or ""
    assert "ORCHID-PY61" in text, f"history check failed: {text!r}"
    summary["checks"].append("multi_turn=PASS")

    # 4. response_format=text
    response = client.chat.completions.create(
        model=args.model,
        messages=[{"role": "user", "content": "Reply exactly: TEXT_FORMAT_OK"}],
        response_format={"type": "text"},
        max_completion_tokens=48,
        temperature=0,
    )
    assert response.choices[0].message.content, "response_format=text returned empty content"
    summary["checks"].append("response_format_text=PASS")

    # 5. tool_choice=none compatibility
    response = client.chat.completions.create(
        model=args.model,
        messages=[{"role": "user", "content": "Reply exactly: TOOL_NONE_OK"}],
        tools=[
            {
                "type": "function",
                "function": {
                    "name": "dummy",
                    "description": "Compatibility-only dummy function",
                    "parameters": {"type": "object", "properties": {}},
                },
            }
        ],
        tool_choice="none",
        max_completion_tokens=48,
    )
    assert response.choices[0].message.content, "tool_choice=none returned empty content"
    summary["checks"].append("tool_choice_none=PASS")

    # 6. Streaming + usage
    pieces = []
    usage_seen = False
    stream = client.chat.completions.create(
        model=args.model,
        messages=[{"role": "user", "content": "Reply exactly: PY_STREAM_OK"}],
        max_completion_tokens=48,
        temperature=0,
        stream=True,
        stream_options={"include_usage": True},
    )
    for chunk in stream:
        if chunk.usage is not None:
            usage_seen = True
        if chunk.choices:
            delta = chunk.choices[0].delta.content
            if delta:
                pieces.append(delta)

    streamed_text = "".join(pieces)
    assert streamed_text.strip(), "streamed assistant content is empty"
    assert usage_seen, "stream usage chunk was not observed"
    summary["checks"].append("streaming=PASS")
    summary["stream_text"] = streamed_text

    summary["result"] = "PASS"
    write_json(out_dir / "SUMMARY.json", summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
