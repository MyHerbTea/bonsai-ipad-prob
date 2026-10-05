# RC1.26 Phase 2A — Memory Governor Observer

Phase 2A introduces an observe-only Metal-aware memory governor.

## Safety boundary

- `bb.governor.metalAware` may become effective only in the EXPERIMENTAL profile.
- It classifies pressure and recommends an action.
- It does not release resident model state, clear MLX caches, clear llama KV, change context admission, downgrade Vision, or alter generation.
- `bb.heapPressureRelief` remains the separate actuator and is OFF in Phase 2A.
- Every automated run restores BASELINE before exit.

## Pressure inputs

- process available memory;
- resident / physical footprint;
- Metal current allocated size;
- Metal recommended working set;
- Metal headroom ratio;
- thermal state.

## Grades

- nominal: observe;
- guarded: observe and avoid optional growth;
- constrained: eligible for later heap-pressure relief;
- critical: later actuator may block optional growth and relieve memory.

## Device gate

The ABAB campaign alternates BASELINE → GOVERNOR and repeats. Promotion in Phase 2A means only that the observer is trustworthy and low-overhead. It does not promote any memory-release behavior.
