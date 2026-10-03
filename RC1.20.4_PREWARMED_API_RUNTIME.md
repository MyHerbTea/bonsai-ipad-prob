# RC1.20.4 — Prewarmed API Runtime

## Evidence motivating this change

RC1.20.3 established two facts:
- multimodal API no longer process-crashed when StagedVisionBridge was bypassed; it returned a structured HTTP 500 from projector-first model loading;
- a clean-process text-only API request still caused a connection reset / app termination.

The Developer Diagnostics view still showed stale staged markers, so the previous stage evidence was insufficient for the text crash.

## Architecture change

The HTTP request handler no longer owns model/context lifecycle.

When the user taps Start OpenAI API:
1. unload existing runtime;
2. load the 27B GGUF;
3. create a conservative 512-token llama context;
4. if mmproj is selected, load the vision projector and recreate the vision context;
5. only after all runtime preparation succeeds, start listening on port 8080.

After the listener is ready:
- text requests call generateText only;
- image requests call generateVision only;
- no request performs loadModel, loadVision, loadVisionProjectorFirst, or unloadAll.

Stopping the API releases the resident runtime.

## Crash forensics

BonsaiEngine.mark now also writes Application Support/bonsai_engine_stage.txt.
loadModel records MODEL_00_RESET_BEGIN and MODEL_00_RESET_DONE around unloadAll.
Developer Diagnostics displays Engine Stage separately from the legacy staged-vision file.

This means a prewarm crash can distinguish reset, backend init, file scope, full-model load, and llama-context creation without relying on stale STAGED_* markers.
