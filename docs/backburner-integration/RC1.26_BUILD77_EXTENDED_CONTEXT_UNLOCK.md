# RC1.26 Build 77 — M5 Extended Context Unlock

## Goal

Restore practical usability immediately. Build 77 removes the UI-only 2048 ceiling and exposes the context range already accepted by `RuntimeConfig.validated()`.

## Context ladder

- 512 — legacy
- 768 — legacy
- 1024 — legacy
- 2048 — certification baseline
- 3072 — transition tier
- 4096 — **recommended daily starting point**
- 6144 — aggressive
- 8192 — extreme

Fresh installs default to 4096. Existing installs may retain their previously selected context and can switch after stopping the API.

## Important separation from Build 76 KV reuse

The first Build 76 device run proved that its partial-tail Text KV strategy does not actually reuse KV on this model/runtime: `llama_memory_seq_rm` tail removal returns false and the code safely falls back to full prefill.

Build 77 intentionally does **not** pretend that issue is fixed. It prioritizes usable capacity first. KV reuse redesign remains a separate follow-up.

## Frozen boundaries

Build 77 keeps:

- Build 75 API cold-start guard;
- Full / Accelerated runtime behavior;
- Phase2F 32/32 prefill launch shape;
- Metal Tensor disabled;
- existing Vision and MLX sidecar paths;
- current fallback/full-prefill behavior.

## Recommended device order

1. Install Build 77.
2. Stop API if it is running.
3. Select 4096.
4. Start/prewarm API.
5. Verify `/health` reports `context_window=4096`.
6. Use 4096 normally.
7. Then probe 6144 and 8192 only if memory/headroom and stability remain healthy.

The product runtime validator already permits up to 8192; this build exposes that capability in the production UI.
