# NEXT STAGE AFTER RC1.24.1

## Frozen conclusion

RC1.24.1 Build 56 completed the runtime-profile attribution study.

Production default remains:

- Flash Attention: ON
- KQV Offload: ON
- Op Offload: ON
- API context: 512
- batch / ubatch: 8 / 8
- load mode: mmap
- unified KV: ON

Do not regress this configuration.

## What not to do next

Do not:
- replace Full with Safe;
- insert 15–60 second sleeps between normal API requests;
- unload/reload the 27B runtime between requests;
- automatically switch profiles after a fixed number of requests;
- claim that ProcessInfo thermal=nominal proves there is no SoC power/DVFS
  behavior.

Those approaches either reduce real wall-clock performance or are unsupported
by the evidence.

## Recommended next direction

The synthetic ten-request stress test has answered the configuration question.
Further useful work should now target user-visible product value rather than
chasing the same device-level recovery curve.

Priority order:

1. Preserve Full as the production runtime baseline.
2. Keep Build 55/56 diagnostics available for regressions.
3. Move to practical interactive/API workloads, where natural user think-time
   already creates recovery gaps.
4. Continue the product roadmap: multimodal usability, multi-image request
   handling, clearer error reporting, and API compatibility.
5. If sustained decode again becomes a blocker in a real workload, create a
   separate Metal-level profiling stage using command-buffer timing /
   Instruments evidence before changing the inference configuration.

No Build 57 performance hack is justified by the current data.
