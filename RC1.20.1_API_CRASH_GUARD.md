# RC1.20.1 — LAN Multimodal API Crash Guard

Observed on real iPad M5:
- TCP /health and /v1/models all passed.
- A 908635-byte POST to /v1/chat/completions uploaded completely.
- The client then received connection reset because the Bonsai process exited.
- On relaunch the persisted native stage was STAGED_07_CONTEXT_BEGIN.

Interpretation:
The request crossed HTTP parsing, authentication, image decode/encode/cache and full-model loading. The process terminated during native llama context creation, before Swift could catch an error and run the normal accelerated-to-safe fallback.

Hotfix:
- Only LAN multimodal requests start with VisionInferenceMode.safe.
- Standard 768 quality and the requested output budget remain unchanged.
- The normal in-app vision path still uses the user's Accelerated/Safe selection.
- Safe API requests remain eligible for resident model/context/KV reuse across compatible repeated calls.

Acceptance:
1. Same 0.87 MiB multimodal POST must no longer terminate the app.
2. It must return HTTP 200 + chat completion or a structured HTTP error.
3. A second compatible request should remain stable and may report warm-session reuse in diagnostics.
4. After this safety proof, accelerated LAN cold-start can be reintroduced experimentally behind an explicit guard rather than being the default.
