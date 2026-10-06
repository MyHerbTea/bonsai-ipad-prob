# RC1.26 Phase 2G0 — Sustained Decode Device Evidence

Captured: 2026-10-06 23:56 +08:00

## Verdict

**PASS MEASUREMENT / REPRODUCED SUSTAINED-DECODE DECAY / DO NOT BUILD 76 YET**

Parent:
- Build 75 device-certified binary: `c09b2e09706dd0c0391b7a15727da57e0f17d425`
- runtime shape: 32×32
- context: 2048
- Metal Tensor disabled

Workload:
- text-only
- fixed integer continuation prompt
- prompt tokens: 85
- max_tokens: 128
- temperature: 0
- top_p: 1
- seed: 424242
- one excluded warmup + five measured requests
- all requests ended by `length`
- all requests produced 128 completion tokens

## Results

Warmup:
- prefill: 1,263.088 ms
- decode-to-first: 596.156 ms
- TTFT: 1,859.244 ms
- sustained decode: 13.480 tok/s

Measured requests:

| Request | Prefill ms | Decode-to-first ms | TTFT ms | Decode tok/s |
|---|---:|---:|---:|---:|
| measure_1 | 1,257.544 | 592.080 | 1,849.625 | 12.676 |
| measure_2 | 1,252.357 | 597.851 | 1,850.209 | 12.570 |
| measure_3 | 1,297.438 | 618.774 | 1,916.212 | 12.129 |
| measure_4 | 1,324.057 | 629.071 | 1,953.128 | 11.912 |
| measure_5 | 1,338.116 | 636.700 | 1,974.816 | 11.061 |

Five-request averages:
- avg prefill: 1,293.902 ms
- avg decode-to-first: 614.895 ms
- avg TTFT: 1,908.798 ms
- avg sustained decode: 12.070 tok/s
- min/max sustained decode: 11.061 / 12.676 tok/s
- sustained-decode CV: 4.780%

Trend:
- measure_1 → measure_5 sustained decode: **-12.742%**
- warmup → measure_5 sustained decode: **-17.947%**
- measure_1 → measure_5 prefill latency: **+6.407%**
- measure_1 → measure_5 decode-to-first latency: **+7.536%**
- measure_1 → measure_5 TTFT: **+6.768%**

## Resource evidence

Thermal state remained `nominal` before and after every request.

After warmup, persistent memory growth was very small:
- measure_1 start resident → measure_5 end resident: +327,680 bytes
- measure_1 start footprint → measure_5 end footprint: +229,376 bytes
- available memory changed by roughly the same small magnitude
- Metal allocation reached a stable plateau and was flat from measure_3 onward

This does **not** look like a simple monotonic memory leak or steadily growing Metal allocation.

## Interpretation

The same broad failure mode documented in RC1.24.0 is still observable:
continuous requests lose decode throughput while iPadOS thermal state stays nominal.

The current evidence does not justify a product-code change yet. The next discriminating experiment is an idle-recovery test on the same Build 75 process:
1. drive the runtime into the degraded state;
2. wait 60 seconds without unloading the model or restarting the app;
3. rerun the identical 128-token request.

Interpretation gate:
- strong recovery after idle → prioritize power/frequency/device-state explanation;
- no recovery after idle → investigate persistent runtime/Metal state;
- partial recovery → run listener stop/resume and full-runtime reload matrix before Build 76.

## Evidence integrity

Uploaded ZIP:
- `rc126-phase2g0-sustained-decode-20261006-235626.zip`
- SHA-256: `cf5d3c7f8182cd802c1abb1ec4836608fb1273f1f5a27161beac3695257f191e`

### Runner issue discovered

The raw JSON evidence is valid. However, `summary.csv` is malformed because the PowerShell function emits `Format-List` formatting objects into the output pipeline before returning the row object. Future runners must render human-readable rows with `Write-Host` or `Out-Host` so formatting objects cannot contaminate CSV export.
