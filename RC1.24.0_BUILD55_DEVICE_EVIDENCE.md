# RC1.24.0 Build 55 — Device Evidence Closure

Status: **DIAGNOSIS CONVERGED**

Device:
- iPad Pro M5
- iPadOS 27.0.1
- physical memory: 11524 MiB
- model: Ternary-Bonsai-2-27B-PTQ1_0.gguf
- API context: 512
- batch/ubatch: 8/8
- output budget: 128 tokens
- fixed text prompt: 83 prompt tokens

## Accelerated / Full sustained decode

Observed server decode throughput over ten consecutive text-only requests:

13.592, 12.626, 10.748, 8.101, 9.018, 8.895, 8.560, 8.374, 8.150, 8.066 tok/s.

The first request decoded 128 tokens in 9.417 s. The tenth required 15.869 s.
The decline reproduced with Vision completely absent.

Throughout the run:
- iPadOS thermal state remained nominal;
- Low Power Mode remained disabled;
- app scene phase remained active;
- Metal allocation was essentially flat near 5858 MiB;
- resident/footprint memory did not show cumulative growth.

## Recovery timing

Controlled recovery probes showed that the slowdown is reversible without
reloading the 27B resident runtime:

- sustained slow state: about 7.4–8.3 tok/s;
- 15 s idle: 9.195 tok/s;
- 30 s idle: 11.269 tok/s;
- exact 61.193 s idle: 12.856 tok/s;
- long idle: about 13.2–13.45 tok/s.

A listener Stop/Resume was not required for recovery.

This strongly supports a device-level sustained-performance / power / DVFS /
memory-bandwidth effect. It does not by itself prove a specific GPU clock or
power mechanism because private hardware clock telemetry is not available.

## Safe profile comparison

Safe disables Flash Attention, KQV offload and Op Offload.

Ten consecutive Safe requests produced:

8.655, 7.505, 6.244, 6.637, 6.504, 6.378, 6.300, 6.053, 6.150, 5.913 tok/s.

Safe was slower both cold and sustained. It also shifted substantially more
work to the CPU: process CPU utilization was roughly 47–57% during the run,
versus roughly 1% in the sustained Accelerated path.

Therefore:
- Safe is not a performance solution;
- the Accelerated path remains the production default;
- the next experiment must isolate acceleration components instead of
  replacing Full with Safe.

## Closure

Build 55 is frozen as the sustained-decode diagnostic baseline.
No inference optimization is included in Build 55.

Next stage: RC1.24.1 Build 56 — controlled runtime profile ladder.
