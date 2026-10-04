# RC1.24.1 Build 56 — Runtime Profile A/B Device Evidence

Status: **DEVICE A/B CONVERGED — FROZEN**

Device baseline:
- iPad Pro M5
- iPadOS 27.0.1
- physical memory: 11524 MiB
- model: Ternary-Bonsai-2-27B-PTQ1_0.gguf
- API context: 512
- batch / ubatch: 8 / 8
- fixed prompt: 83 prompt tokens
- fixed output: 128 completion tokens
- app foregrounded
- Low Power Mode: OFF
- ProcessInfo thermal state: nominal throughout

## Controlled profile ladder

| Profile | Flash Attention | KQV Offload | Op Offload |
|---|---:|---:|---:|
| Safe | OFF | OFF | OFF |
| Flash | ON | OFF | OFF |
| +KQV | ON | ON | OFF |
| Full | ON | ON | ON |

All four profiles used the same prompt, output budget and text-only route.

## Server decode throughput

### Safe
8.655, 7.505, 6.244, 6.637, 6.504, 6.378, 6.300, 6.053, 6.150, 5.913 tok/s

- 10-request mean: 6.634 tok/s
- last-5 mean: 6.159 tok/s
- request 10: 5.913 tok/s

### Flash only
8.831, 8.791, 6.293, 6.893, 6.820, 6.620, 6.523, 6.481, 6.432, 6.326 tok/s

- 10-request mean: 7.001 tok/s
- last-5 mean: 6.476 tok/s
- request 10: 6.326 tok/s

### Flash + KQV
13.334, 8.327, 7.758, 8.126, 7.918, 7.774, 7.664, 7.623, 7.561, 7.475 tok/s

- 10-request mean: 8.356 tok/s
- last-5 mean: 7.619 tok/s
- request 10: 7.475 tok/s

### Full
13.558, 12.560, 7.980, 8.353, 8.822, 8.230, 8.240, 8.113, 7.995, 7.844 tok/s

- 10-request mean: 9.170 tok/s
- last-5 mean: 8.084 tok/s
- request 10: 7.844 tok/s

## Incremental attribution

Relative to the immediately lower profile:

- Flash over Safe:
  - 10-request mean: +5.5%
  - last-5 mean: +5.2%

- KQV over Flash:
  - 10-request mean: +19.4%
  - last-5 mean: +17.6%

- Op Offload over Flash+KQV:
  - 10-request mean: +9.7%
  - last-5 mean: +6.1%

The largest single measured acceleration step is KQV Offload.

## CPU / Metal behavior

Safe and Flash-only retain high process CPU participation:
- Safe: roughly 47–57% process CPU estimate
- Flash-only: roughly 40–48%

Flash+KQV and Full move process CPU participation to roughly 1% during sustained decode.

Metal allocation:
- Flash-only: about 5678 MiB
- Flash+KQV / Full: about 5858 MiB

This is strong evidence that KQV Offload is the transition that moves a
substantial part of the workload away from CPU participation and into the
accelerated Metal path.

## Sustained slowdown remains

Full is the fastest profile but still exhibits reversible sustained-load
degradation:

- initial burst: about 13.6 tok/s
- sustained region: about 8 tok/s
- exact idle recovery work from Build 55 showed:
  - 15 s idle: partial recovery
  - 30 s idle: stronger recovery
  - about 60 s idle: near-full recovery

The slowdown is therefore not solved by disabling acceleration features.
Safe is slower and still degrades.

## Closure

1. **Full / Accelerated remains the production default.**
2. **KQV Offload is the largest measured acceleration contributor.**
3. **Op Offload provides a smaller but measurable additional gain.**
4. **Flash Attention alone provides only a modest gain.**
5. **No tested profile eliminates the reversible sustained-load slowdown.**
6. **Do not add automatic cooldown, reload, or profile switching merely to
   optimize the synthetic back-to-back stress test.**
7. Build 56 is frozen as the controlled runtime-profile attribution baseline.

The remaining slowdown is best treated as a device-level sustained-performance
characteristic unless future Metal-level telemetry proves a software-local
cause.
