# RC1.23.1 Source Map

Base branch: `lab-v1-rc1-23-live-vision-injection`
Base commit: `ca5b29fefe9bb1a49b78615c7d61a6b170aa62f6`

## Frozen integration points

- Text/LAN OpenAI server: `BonsaiLab/LocalOpenAIServer.swift`
  - `OpenAIRequestPayload`
  - `LocalOpenAIServer.start(port:handler:)`
  - `parseChatPayload`
  - existing chunked SSE machinery
- Resident 27B runtime and BVCACHE1 prefill: `BonsaiLab/BonsaiEngine.swift`
  - `writeMLXProjectedVisionCache(...)`
  - `generateCachedVision(...)`
  - `generateText(...)`
- MLX Hard Graph-Cut vision path: `BonsaiLab/BonsaiMLXVisionSidecar.swift`
  - `MLXVisionSidecar.encodeForInjection(weightsURL:imageURL:)`
  - output packet contains F32 embeddings + gridX/gridY
- Qwen/Bonsai M-RoPE cache/prefill bridge: `BonsaiLab/StagedVisionBridge.mm`
  - `BonsaiWriteProjectedVisionCache`
  - `BonsaiPrefillCachedVision`
- Product wiring: `BonsaiLab/ProductionView.swift`
  - `runLiveVisionInjection()`
  - `startAPIServer()`
- Runtime/error types: `BonsaiLab/LabTypes.swift`

## Rulings from source inspection

1. **Image ordering constraint.** RC1.23.0 prefill is fixed vision-first inside the user message:
   `<|vision_start|>[visual]<|vision_end|>\nquestion`.
   RC1.23.1 will preserve incoming content-part order in normalization metadata but will explicitly adapt the single-image API request to this frozen runtime constraint instead of pretending arbitrary interleaving is supported.

2. **Context accounting.** MLX output rows and M-RoPE positions are different quantities. The validated reference packet is 54 projected rows at width 5120, while `BonsaiWriteProjectedVisionCache` stores `n_pos = max(grid_x, grid_y) = 9`. Admission therefore uses the actual `BonsaiPrefillCachedVision.input_positions`, not a simplified assumption that every visual row consumes one sequential position.

3. **API image backend.** RC1.23.1 replaces only the LAN image branch. The old mmproj two-phase implementation remains available to other product/diagnostic flows but is no longer the OpenAI API image backend.

4. **No silent fallback.** Any supplied image that fails parsing, MLX vision, cache bridge, context admission, or live injection returns a structured API failure and never continues through `generateText`.
