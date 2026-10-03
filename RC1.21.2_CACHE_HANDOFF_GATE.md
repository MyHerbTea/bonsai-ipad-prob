# RC1.21.2 — Cache Handoff Gate

## Real-device evidence

RC1.21.1 successfully passed Phase A far enough to persist the image embedding cache and then reloaded the full 27B model. The process terminated at:

MODEL_07_CONTEXT_CREATE_BEGIN

Therefore:
- projector/mmproj work completed;
- full 27B GGUF reload completed;
- the fatal boundary is creating a new llama context after projector activity in the same process.

This matches the earlier staged-vision API failures and is independent of the cache-key security-scope issue fixed in RC1.21.1.

## Safety rule

Never create a fresh full-model llama context in a process that has already executed mtmd/projector work.

## RC1.21.2 behavior

Cache MISS:
1. release the RC1.20.7 text runtime;
2. run vocab-only + Q8 mmproj;
3. encode the image;
4. persist BVCACHE1 projected embeddings + M-RoPE positions;
5. release projector/vocab-only/backend state;
6. DO NOT recreate the 27B model/context;
7. return HTTP 409 vision_cache_prepared_restart_required.

After a clean App process restart:
1. Start OpenAI API normally; 27B + text context prewarm in a clean process.
2. Re-send the exact same image request.
3. Content-addressed cache lookup must HIT.
4. No mmproj/projector initialization occurs.
5. Cached image embeddings are injected directly into the stable text llama context.
6. Generate the answer.

## Acceptance goal

This is a diagnostic architecture gate, not final UX.

PASS requires:
- first cold request returns structured 409 rather than crashing;
- after a full app restart, same image request returns HTTP 200;
- Two-Phase stage reaches TWOPHASE_B99_PREFILL_READY / TWOPHASE_VISION_99_PASS;
- answer correctly reflects image content.

If this passes, the remaining engineering problem is isolation of Phase A into a separate iOS process/extension/worker so the handoff can become transparent to the user without sacrificing the frozen text runtime.
