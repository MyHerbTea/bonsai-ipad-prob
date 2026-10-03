# RC1.15 Product Session Integration

## Source lines

- Product/API parent: `lab-v1-rc1-13-openai-lan-api` (Run #42 green)
- Performance source: `lab-v1-rc1-14-resident-llm-session` (Run #36 build green)
- New integration branch: `lab-v1-rc1-15-product-session-integration`

## Why a new branch

RC1.13 OpenAI LAN API and RC1.14 resident-model work diverged. RC1.14 does not
contain `LocalOpenAIServer.swift` or `PRODUCTIZATION_PROTOCOL.md`, so promoting
RC1.14 directly would regress product/API functionality.

## Integration fixes

1. Port image-embedding cache and resident full-model bridge from RC1.14.
2. Preserve the RC1.13 production UI and OpenAI-compatible LAN API.
3. Fix `runStagedVision()` so it does not call the default resident-releasing
   `unloadAll()` before every request.
4. Release resident state and stop the LAN API when the production app enters
   the background.
5. Release stale resident state immediately when the selected model or mmproj
   changes.
6. Expose cache/resident HIT/MISS in diagnostics and certification output.

## Device acceptance

Use PTQ1_0 + Q8 mmproj + the same representative image. Run one normal request,
then ask another question with the same image/quality. The second request should
show both cache and resident model HIT, with image encode and full-model load
near zero. Then run the one-tap device certification; a second certification
run should show warm reuse for the previously cached tiers.

Do not promote RC1.15 over RC1.13 until this real-device acceptance passes.
