# RC1.26 Phase 2G2 — Paced vs Burst Device Evidence

Captured: 2026-10-07 00:46 +08:00

## Verdict

**CLOSE SUSTAINED-DECODE INVESTIGATION / DUTY-CYCLE DEPENDENT / NO BUILD 76 PERFORMANCE HACK**

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
- phase A: five back-to-back requests
- reset: 60 seconds idle
- phase B: five identical requests with 15-second gaps

All ten requests produced exactly 128 completion tokens.

## Results

### Burst

| Request | Prefill ms | First-token ms | TTFT ms | Decode tok/s |
|---|---:|---:|---:|---:|
| burst_1 | 1373.426 | 595.468 | 1968.895 | 13.461 |
| burst_2 | 1238.366 | 596.993 | 1835.360 | 12.951 |
| burst_3 | 1280.132 | 606.667 | 1886.799 | 12.395 |
| burst_4 | 1311.109 | 624.144 | 1935.253 | 12.030 |
| burst_5 | 1335.864 | 633.119 | 1968.984 | 9.557 |

Burst:
- mean sustained decode: **12.079 tok/s**
- first → last: **-29.002%**
- decode CV: **11.189%**
- avg prefill: **1307.779 ms**
- avg first-token: **611.278 ms**
- avg TTFT: **1919.058 ms**

### Paced — 15-second gaps

| Request | Prefill ms | First-token ms | TTFT ms | Decode tok/s |
|---|---:|---:|---:|---:|
| paced_1 | 1261.865 | 592.672 | 1854.537 | 12.976 |
| paced_2 | 1260.460 | 592.267 | 1852.727 | 12.858 |
| paced_3 | 1255.218 | 595.122 | 1850.340 | 13.112 |
| paced_4 | 1261.083 | 590.903 | 1851.986 | 12.732 |
| paced_5 | 1254.727 | 595.002 | 1849.730 | 13.026 |

Paced:
- mean sustained decode: **12.941 tok/s**
- first → last: **+0.385%**
- decode CV: **1.027%**
- avg prefill: **1258.671 ms**
- avg first-token: **593.193 ms**
- avg TTFT: **1851.864 ms**

Comparison:
- paced average vs burst average: **+7.136%**
- paced slope is effectively flat while burst falls 29%
- paced first-token latency is ~18 ms lower on average
- paced prefill and TTFT are also more stable

## Resource observations

- thermal remained `nominal → nominal` for every request;
- burst Metal allocation stopped growing after early initialization;
- paced requests repeatedly returned to a lower available-memory / footprint operating point during the 15-second gaps;
- no monotonic memory or Metal allocation leak explains the burst slowdown.

The result is fully consistent with a reversible duty-cycle / device operating-state effect. iPadOS `ProcessInfo.thermalState` is too coarse to rule out CPU/GPU DVFS, power-budget changes, scheduler state, or similar mechanisms.

## Cross-version corroboration

RC1.24.1 Build 56 already established:
- Full / Accelerated was the fastest runtime profile;
- disabling KQV / Op Offload did not remove sustained slowdown;
- 15 s idle gave partial recovery;
- 30 s idle gave stronger recovery;
- ~60 s idle gave near-full recovery;
- automatic cooldowns or profile switching were not justified.

Build 75 / Phase 2G0–2G2 reproduces the same class of behavior after the major prefill improvements:
- 32×32 remains the correct runtime shape;
- Full / Accelerated remains the correct runtime profile;
- synthetic continuous-load slowdown remains reversible and duty-cycle dependent.

## Closure

Do not:
- insert artificial 15–60 second sleeps into production;
- unload/reload the 27B runtime between normal requests;
- disable KQV or Op Offload;
- return to Safe profile;
- re-enable Metal Tensor;
- test 64/128 batch;
- create Build 76 solely to hide this synthetic stress-test behavior.

Treat this as a device-level sustained-performance characteristic unless a real user workload demonstrates that it is a product blocker.

Next work should validate Build 75 under practical API workloads and product flows.

Evidence ZIP:
- `rc126-phase2g2-paced-ab-20261007-004649.zip`
- SHA-256: `f9c78f240f2cd463f8ef2af09c7ad8c41248c3ee6a39c8c9b3decde434bbbfe6`
