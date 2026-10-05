# RC1.26 Phase 2B — Heap Pressure Relief

Phase 2B is the first RC1.26 optimization stage that may change runtime behavior.

## Actuator

The actuator calls Darwin `malloc_zone_pressure_relief(NULL, 0)` through `SystemProbeBridge`. It asks the malloc subsystem to return releasable allocator pages. It does not unload the resident 27B model, clear llama semantic memory, or mutate MLX model state.

## Automatic safety gate

Automatic relief requires all of:
- profile = EXPERIMENTAL;
- `bb.governor.metalAware=true`;
- `bb.heapPressureRelief=true`;
- governor grade is constrained or critical.

Nominal and guarded grades do not automatically trim.

## Device certification

The Phase 2B runner alternates BASELINE and RELIEF. RELIEF performs a fixed text request, invokes authenticated forced trim for observability, and then performs a post-trim inference liveness request. The runner always restores BASELINE.
