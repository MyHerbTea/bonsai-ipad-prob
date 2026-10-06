# RC1.26 Phase 2G — Sustained Decode Closure

Status: **CLOSED — NO PRODUCT CHANGE**

Evidence chain:
1. Phase 2G0: sustained decode decays during back-to-back 128-token requests.
2. Phase 2G1: 60-second idle restores +16.338% decode throughput.
3. Phase 2G2: 15-second pacing removes the downward slope almost completely.

Decision:
- no Build 76 performance patch;
- no automatic cooldown;
- no runtime-profile downgrade;
- no batch change;
- preserve Build 75 Stable Checkpoint.

The behavior is considered a reversible duty-cycle/device-operating-state characteristic for the current evidence set.

Next stage: practical RC1.26 certification on representative user/API workloads.
