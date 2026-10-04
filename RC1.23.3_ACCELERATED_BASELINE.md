# RC1.23.3 Accelerated Performance Baseline — Build 45 FROZEN

Build 44 target-device evidence selects **Full / Accelerated** as the recommended runtime profile.

- Safe 6-HIT average: ~22.95 s.
- Accelerated 6-HIT average: ~18.73 s (~18% faster).
- Accelerated 12-HIT soak: 13/13 HTTP 200.
- 12 warm HIT average: ~19.34 s.
- HIT2–12 average: ~19.92 s.
- Final six warm HIT average: ~20.24 s.
- Final-six throughput: ~7.27 tok/s.
- Metal allocation stayed ~6110 MiB.
- C2-B stayed HIT + retained=true; warm prefix/image prefill stayed zero.
- No crash or monotonic resource accumulation was observed.

Status: **FROZEN**\n\nBuild 45 changes product selection only:
- Accelerated becomes the fresh-install default.
- Safe remains the compatibility fallback.
- Flash-only is hidden and stale Flash selections migrate to Accelerated.
- C2-B checkpoint semantics and n_seq_max=1 are unchanged.

Next stage: generation/decode efficiency and OpenAI max-token semantics.
