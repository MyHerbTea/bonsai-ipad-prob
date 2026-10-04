# Next Stage After RC1.23.2 Frozen Baseline

Starting point: **RC1.23.2 build 41 frozen C2-B baseline**.

Executable source baseline:

`990e8d6d90a660461fa14c4d391202efb2eb0bd5`

Do not reopen C1 partial trimming or C2-A `n_seq_max=2`.

## Recommended next version

**RC1.23.3 — Production Hardening and Secondary Latency Work**

The next version should treat C2-B as a frozen subsystem rather than as an
active experiment.

### Priority 1 — Preserve C2-B

No change may regress:

- single-sequence context creation;
- ON_DEVICE prefix-state save/restore;
- image/system identity matching;
- text/failure/unload invalidation;
- warm HIT prefix/image prefill = 0;
- isolation and recovery behavior.

If a change touches these boundaries, rerun the RC1.23.2 controlled A/B,
isolation sequence and 10-hit soak.

### Priority 2 — Separate long-run throughput from checkpoint correctness

The 10-hit soak showed later latency/throughput degradation while the checkpoint
remained a valid HIT and prefix/image prefill stayed zero.

Treat this as a separate observability problem:

- distinguish thermal/device throttling from llama runtime degradation;
- record per-request decode tok/s and suffix prefill over time;
- avoid changing C2-B state semantics merely to chase transient slowdown;
- require evidence before assigning the slowdown to memory or state leakage.

### Priority 3 — Reconsider Phase B only as a secondary optimization

Vision encode + cache-write cost is small relative to the original 27B prefill
bottleneck. It may still be optimized later, but it must not destabilize the
frozen C2-B path.

Any embedding-cache work should:

- preserve BVCACHE1;
- remain content-addressed;
- keep existing invalid-image/error behavior;
- measure actual saved milliseconds on device;
- be reverted if complexity exceeds the measured gain.

### Priority 4 — Productization

Before enabling prefix reuse by default, explicitly decide:

- whether the experimental toggle becomes a production setting;
- how diagnostics expose HIT/MISS without overwhelming normal users;
- whether API startup should report the active reuse mode;
- how a future user can intentionally clear warm state.

Default behavior should remain conservative until those UX decisions are made.

## First task in the next development window

Start with a read-only baseline audit:

1. verify branch HEAD and build number;
2. read `RC1.23.2_FROZEN_BASELINE.md`;
3. re-run source/contract checks without changing code;
4. identify one next-version objective only;
5. create a new branch/version before implementation.

Do not modify RC1.23.2 frozen behavior in-place.
