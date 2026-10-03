# RC1.20.3 — API Swift Vision Bypass

RC1.20.2 real-device evidence:
- LAN request still terminated the app.
- persisted staged boundary: STAGED_07_CONTEXT_BEGIN.
- preflight before native staged execution:
  - available: 5090 MiB
  - resident: 100 MiB
  - phys footprint: 29 MiB
  - Metal allocated: 0 MiB
  - Metal recommended working set: 8192 MiB
- resident staged state had already been released.
- context was only 256, image tokens 64, batch/uBatch 4, safe mode.

Therefore low pre-request headroom, accelerated attention flags, 768 context and resident-state retention are not plausible primary causes.

## Controlled A/B

LAN multimodal requests only now bypass StagedVisionBridge entirely.

They use the already-existing Swift/Prism path:
1. unload all state;
2. loadVisionProjectorFirst(..., VisionConfig.low512);
3. create the llama context through BonsaiEngine.makeContext;
4. run generateVision via mtmd_helper_eval_chunks;
5. stream generated text through the existing onDelta callback.

The in-app product vision route remains staged and unchanged.

## Interpretation

- API succeeds: root cause is isolated to StagedVisionBridge / its packet-cache-context lifecycle, not HTTP, Prism in general, or the 27B model.
- API still crashes during MODEL/BOOT context creation: investigate generic API-thread/context lifecycle or backend/model residency rather than staged packet handling.
