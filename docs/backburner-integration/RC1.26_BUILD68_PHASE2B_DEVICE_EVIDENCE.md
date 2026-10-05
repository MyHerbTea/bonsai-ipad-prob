# RC1.26 Build 68 Phase 2B Device Evidence

Status: **PASS — SAFE_NO_RECLAIM_OBSERVED**

Device campaign: `20261006-000816`  
Build: `68`  
Build ID: `rc1.26-build68-heap-pressure-relief`

## Result

Phase 2B proved that the guarded Darwin allocator relief actuator is safe on the tested resident 27B runtime, but it did not demonstrate a reclaim benefit under the observed nominal-memory workload.

- Campaign overall: PASS
- Decision: SAFE_NO_RECLAIM_OBSERVED
- Fixed fixture tokens: 35 prompt / 9 completion / 44 total
- BASELINE average: 4325.136 ms
- RELIEF average: 4364.551 ms
- Observed primary-request overhead: 0.911%
- Forced trims performed: 3/3
- Total allocator bytes released: 0
- Maximum native trim duration: 0.005 ms
- Post-trim inference survival: 3/3 PASS
- Unsafe thermal samples: 0
- Health start/end: ok / ok
- Final restored profile: BASELINE

## Memory / Metal observations

All six primary runs reported exactly the same Metal allocation:

`6,248,628,224 bytes`

The campaign started at a physical footprint of `500,389,504` bytes and ended at `500,323,968` bytes, a net change of only `-65,536` bytes. Available memory moved by `+65,536` bytes over the same primary-run window. These tiny deltas are consistent with a stable resident runtime rather than evidence of allocator reclaim.

Each forced `/debug/gc-or-trim` call returned `performed=true`, `reason=debug_forced`, and `bytes_released=0`. Native relief itself was effectively instantaneous; endpoint wall time was about 10–11 ms.

## Promotion decision

Do **not** promote `bb.heapPressureRelief` to ACCELERATED based on Build 68.

Keep it:
- implemented,
- gated behind EXPERIMENTAL,
- available for future constrained/critical pressure experiments,
- default OFF.

The actuator passed safety and liveness checks, but no measurable reclaim benefit was demonstrated in the nominal workload.

## Observability note

The current `last_heap_pressure_relief` field is intentionally persistent. As a result, later BASELINE rows can display the previous forced trim as the "last" record even though no relief occurred in that BASELINE request. Request-boundary sequence deltas of 0 and `behavior_changes_enabled=false` confirm the BASELINE requests did not execute the actuator.

A later cleanup should separate "last relief record" from "relief performed during this request" to avoid ambiguous campaign output.
