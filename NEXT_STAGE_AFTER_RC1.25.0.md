# NEXT STAGE AFTER RC1.25.0

RC1.25.0 Build 57 is frozen and device certified.

Do not modify the frozen branch or certified source commit.

## RC1.25.1 scope

RC1.25.1 should be a small correctness/observability hardening release, not a
new inference architecture.

Priority fixes:

1. Correct multi-image telemetry:
   - preserve `route=vision_multi` in success history and latest performance
     diagnostics for 2–3 image requests.

2. Improve context admission errors:
   - report input positions;
   - requested output tokens;
   - required context;
   - configured context;
   - maximum safe output budget.

3. Isolate the `Café -> CafÃ©` encoding issue:
   - determine whether corruption originates in model output decoding,
     LocalOpenAIServer JSON serialization, HTTP transport, PowerShell decoding,
     or file encoding;
   - do not change OCR/vision behavior until the layer is identified.

4. Preserve all RC1.25.0 behavior:
   - text API;
   - single-image API;
   - two-image left/right;
   - three-image left/center/right;
   - 3-image maximum;
   - structured invalid-image errors;
   - resident API survival after validation errors;
   - Full/Accelerated production runtime.

## Explicit non-goals

Do not yet:
- replace the contact-sheet adapter with native independent vision blocks;
- increase API context by default;
- alter the 27B runtime profile;
- add automatic cooldown or runtime reloads;
- change image resolution solely on the basis of the current OCR evidence.

A future native multi-image stage should be considered only if real workloads
show that the contact-sheet adapter loses materially important information.
