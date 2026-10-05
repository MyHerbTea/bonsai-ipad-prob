# Next Stage After RC1.25.1

Current stable baseline: **RC1.25.1 Build 60 — DEVICE CERTIFIED / FROZEN**

Frozen branch: `frozen-v1-rc1-25-1-build60-device-certified`

Tested product source:
`5fc6e1cfaea4feb188b0635e26b9772ada83d303`

## Rules

1. Never modify the frozen RC1.25.1 branch after freeze completion.
2. Start any new implementation from the final evidence-only frozen head, not
   from an earlier lab commit.
3. Preserve the Build 60 device-certified behavior as the regression baseline.
4. Do not fold speculative performance fixes into this frozen line.
5. Any future context/runtime change must re-test both rejection and valid
   2-image behavior.

## Baseline that must not regress

- text API;
- single-image API;
- 2-image and 3-image bounded contact-sheet API;
- `vision_multi` telemetry;
- UTF-8 JSON response declaration;
- dual logical-position + physical-KV context admission;
- structured HTTP 400 `context_length_exceeded`;
- cleanup/API survival after rejected requests;
- Accelerated 512 / 8 / 8 production profile.

## Recommended next-stage split

Keep future work modular.

### A. API/runtime evolution

Possible RC1.25.2 work may explore larger context windows, output-budget policy,
or richer context diagnostics. Treat these as explicit runtime changes with
fresh device A/B evidence; do not silently alter the frozen 512 baseline.

### B. Multi-image architecture experiments

Native independent multi-image token blocks can be explored separately from the
certified contact-sheet adapter. The existing adapter remains the fallback and
regression oracle until a replacement is independently device-certified.

### C. Model-family experimentation

Qwen3.8-Flash-Next / alternative quantization work should live on a separate
experimental branch or project line. Do not couple model-format exploration to
the frozen Bonsai-2-27B RC1.25.1 runtime.

### D. Performance work

The sustained decode slowdown observed in RC1.24 remains a device-level
characteristic unless new evidence localizes it. Do not add automatic cooldown,
reload, or profile switching without a separately controlled device study.

## First action in a new development window

Create a new lab branch from the final RC1.25.1 frozen evidence head, define one
narrow scope, run inherited contracts first, and only then add the new
experiment.
