# RC1.26 Phase 2G1 — Idle Recovery Device Evidence

Captured: 2026-10-07 00:10 +08:00

## Verdict

**STRONG IDLE RECOVERY / DO NOT MODIFY PRODUCT CODE YET**

Parent:
- Build 75 certified binary commit: `c09b2e09706dd0c0391b7a15727da57e0f17d425`
- context: 2048
- runtime shape: 32×32
- Metal Tensor disabled

Workload:
- text-only deterministic integer continuation
- 85 prompt tokens
- 128 completion tokens
- finish reason `length`
- temperature 0
- top_p 1
- seed 424242
- five back-to-back load requests
- 60 seconds idle with API/model kept resident
- one identical post-idle request

## Results

| Request | Prefill ms | First-token ms | TTFT ms | Decode tok/s |
|---|---:|---:|---:|---:|
| load_1 | 1313.431 | 595.644 | 1909.075 | 13.464 |
| load_2 | 1257.645 | 592.210 | 1849.855 | 12.724 |
| load_3 | 1262.857 | 599.953 | 1862.810 | 12.458 |
| load_4 | 1253.504 | 595.210 | 1848.713 | 12.352 |
| load_5 | 1315.664 | 624.965 | 1940.629 | 11.158 |
| post_idle | 1260.856 | 593.093 | 1853.949 | 12.981 |

Idle recovery:
- sustained decode: **11.158 → 12.981 tok/s = +16.338%**
- first-token latency: **624.965 → 593.093 ms = 5.100% faster**
- prefill latency: **1315.664 → 1260.856 ms = 4.166% faster**
- TTFT: **1940.629 → 1853.949 ms = 4.467% faster**

The post-idle decode rate recovered to within **3.6%** of load_1.

## Resource evidence

- thermal state was `nominal → nominal` for every request;
- Metal allocation was unchanged across the 60-second idle and post-idle request;
- idle interval reduced resident memory and physical footprint before the post-idle request;
- no monotonic resident/Metal growth explains the throughput decay.

The coarse iPadOS thermal state does not rule out DVFS/power/frequency changes while still reporting `nominal`.

## Interpretation

This strongly favors a **reversible device/runtime operating-state effect** over:
- a persistent Metal allocation leak,
- irreversible runtime corruption,
- a simple cumulative memory leak.

It is not yet proof of GPU DVFS specifically. CPU/GPU frequency, power budget, scheduler state, or another reversible operating-state mechanism can produce the same signature.

Therefore Build 76 is deferred.

## Next discriminating experiment

Phase 2G2 compares:
- five back-to-back requests,
- 60-second reset idle,
- five identical requests with 15-second pacing gaps.

If pacing materially reduces the downward slope, the sustained-decode problem is duty-cycle/state dependent. If pacing does not help, return to runtime profile and persistent-state isolation.

Evidence ZIP:
- `rc126-phase2g1-idle-recovery-20261007-001010.zip`
- SHA-256: `153fc7a9e8e72915ab1d534a06fbedf183209508b3ecc7f1a77ade7f26c51e35`
