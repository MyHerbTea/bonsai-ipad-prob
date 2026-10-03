# RC1.20.5 — Text API Baseline

## Real-device evidence from RC1.20.4

Starting the API reached:
- 27B model load success;
- text llama context creation success;
- then loadVision released the text context;
- process terminated at VISION_01_MMPROJ_LOAD_BEGIN.

This isolates the immediate crash to mtmd_init_from_file while the full 27B model is resident. It is not an HTTP-server failure and not a generic llama-context creation failure.

## Controlled baseline

RC1.20.5:
1. unloads old runtime;
2. prewarms only the 27B model + conservative 512-token text context;
3. starts port 8080 only after text runtime is ready;
4. text requests call generateText only;
5. image requests return HTTP 503 vision_temporarily_unavailable;
6. no API path initializes mmproj.

The normal in-app vision feature remains unchanged.

## Why this matters

This establishes a stable server/runtime baseline before reintroducing multimodal support. The follow-up multimodal design should avoid ever having mtmd_init_from_file run while the full 27B model is resident.

Planned next architecture:
- Phase A: vocab-only + mmproj + image -> bounded cached image embeddings; release projector completely.
- Phase B: load/reuse the proven Swift 27B text model/context.
- Phase C: inject cached image embeddings into the existing text context without creating a second model/context or reinitializing mmproj.
