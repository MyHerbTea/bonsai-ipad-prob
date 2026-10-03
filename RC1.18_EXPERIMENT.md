# RC1.18 — Resource Governor v1

Derived from the green RC1.17 true-streaming candidate.

## Policy
The governor is deliberately conservative and observable.

1. If the requested image embedding cache exists, preserve the warm resident model/context/KV path.
2. On a cache miss, if process headroom is below 2048 MiB and a staged resident model exists, release resident model/context before projector work.
3. Re-measure headroom after release.
4. Only if headroom is still constrained:
   - below 1536 MiB: detailed/1024 may fall back to standard/768;
   - below 1024 MiB: standard/detailed may fall back to fast/512.
5. Device certification bypasses the governor so 512/768/1024 remain honest fixed-preset tests.

## Diagnostics
Every staged result reports governor state, headroom before/after release, whether resident state was released, and requested/effective image token budgets.

These thresholds are experimental policy constants, not final device calibration.
