# RC1.20.2 — Context Admission Experiment

Real-device evidence from RC1.20 and RC1.20.1:
- the 908635-byte LAN request uploads completely;
- TCP, /health, /v1/models and Bearer auth work;
- both accelerated and safe LAN multimodal paths terminate the app;
- the previously observed persisted native boundary is STAGED_07_CONTEXT_BEGIN.

This falsifies "Flash Attention/KQV is the primary cause".

## RC1.20.2 controlled change

For LAN multimodal cold start only:
1. release all resident model/context/vision state before starting;
2. allow 250 ms for post-release reclamation;
3. persist process headroom, phys_footprint and Metal allocated/recommended sizes;
4. use VisionConfig.probe256:
   - context 256
   - image_max_tokens 64
   - batch 4
   - ubatch 4
5. use safe context mode;
6. cap output to 64 tokens.

The normal in-app vision path remains unchanged.

## Interpretation

- If RC1.20.2 succeeds, the failure is a context-allocation peak/budget issue. Later builds can restore 512/768 through measured admission thresholds.
- If RC1.20.2 still dies at STAGED_07_CONTEXT_BEGIN, context size and accelerated flags are no longer plausible primary causes. The next investigation should focus on full-model GPU residency / Metal allocator pressure or a Prism/llama context-creation defect specific to the in-process LAN service path.

After a crash, relaunching the app should show both the persisted STAGED_* boundary and the API preflight memory snapshot.
