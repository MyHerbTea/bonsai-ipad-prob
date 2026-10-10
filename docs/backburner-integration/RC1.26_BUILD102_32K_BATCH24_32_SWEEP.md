# RC1.26 Build102 — Isolated 32K B16/B24/B32 Batch Sweep

**STATUS: SOURCE CANDIDATE. NO DEVICE RESULTS. NOT STABLE.**

## Protected ancestry
- Frozen Build100 successful iOS CI head: `4e40956e4d2f16d3852ece192ee26b74e34a1da1`.
- New independent branch: `lab-v1-rc1-26-build102-batch24-32-isolated`.
- Same Prism SHA: `adfffbe41b2cabcd51fff326ab045662265062bb`.
- No Build99 APPEND, Build98 FA-vec, memory/vision stack rewrites, context expansion or decode changes.
- 32,768 context only; other contexts keep frozen policies. Q4_0 KV, same PTQ1_0 model, OpenAI stream/nonstream + vision unchanged.

## Existing real-device evidence (not Build102)
| Source | Input/output | Actual n_batch/n_ubatch | Prefill |
|---|---:|---:|---:|
| Build100 B8 | 939/32 | 8/8 | 119.70 s |
| Build100 B16 | 939/32 | 16/16 | 35.25 s |
| Build100 B16 long | 2,135/128 | 16/16 | 109.48 s |
| Build100 Phase A B16 long | 2,135/128 | 16/16 | 89.75 s |

Phase A: 15/15 health observations succeeded while 134 native batches completed. Native cancellation propagation still unproven. No valid evidence for B24 or B32 gain.

## Build102 experiment selection rules
Reuses Build94's proven pre-context process-scoped policy and sticky SAFE4 recovery, rather than a second competing launch state machine. Extended one-shot enum:
- `BASELINE8` (8/8), `CANDIDATE16` (16/16) inherited.
- `CANDIDATE24` (24/24) **only** if local prior B8 and B16 completed successfully.
- `CANDIDATE32` (32/32) **only** if B8, B16, B24 all completed successfully AND request includes `acknowledge_higher_risk: true`.
- `SAFE4` (4/4) sticky recovery. Never bypass explicitly established fallback.
- Candidate starts set a persistent `pending` bit before loading the 32K context, which clears only after a >=200 prompt-token text request completes. Incomplete/startup exception forces SAFE4 at next process launch. Manual recovery must be acknowledged; no implicit rearm.
- All 24/32 experiments are **one-shot**. On successful next launch the selected arm is reset to BASELINE8 for safety. Build100 preference is disabled by explicit 24/32 scheduling, avoiding an unexpected override.
- API scheduling never changes the already allocated llama context. Complete iPad app process restart (not API-only restart) is mandatory before comparing arms.
- Use `GET /debug/build102/launch` and `POST /debug/build102/next-launch` with existing LAN API Bearer authentication. Existing `/debug/build94/*` remains compatible. Inspect `active_arm`, `pending`, `sticky_fallback`, `active_batch`, `active_ubatch`, `engine_context_batch`, `engine_context_ubatch`.
- Candidate scheduling example: `{"arm":"CANDIDATE24"}`. To rearm B16: `{"arm":"CANDIDATE16"}`. To request B32 *after* B24 certification: `{"arm":"CANDIDATE32","acknowledge_higher_risk":true}`. Recovery: `{"arm":"BASELINE8","acknowledge_recovery":true}`; only with deliberate user action.

## Primary device test: B16 -> B24 -> B16 (no B32 until gate)
- Fixed 939-token prompt and max output 32, identical sampling seed/settings, correct input/output SHA256 comparison. Use the same model, exact 32768 context, Q4_0 KV.
- For B16 baseline: B16 must be confirmed and active 16/16 before each timed request. Save evidence before changing arm.
- Schedule B24 via authenticated API, verify `next_arm=CANDIDATE24`, fully close iPad process, reopen API, **verify** `active_arm=CANDIDATE24` and actual 24/24 before timed request.
- After a successful B24, schedule B16, restart and run identical baseline. Analyze 3 Prefill/e2e runs, hash parity, native batch duration and count, phase-A health liveness, memory physical footprint/available MiB, Metal allocations, thermal and errors.
- If B24 speed differs by <10–15% on representative inputs or any safety/correctness issue occurs, do not enable B32. The performance threshold is a *promotion decision*, not a promised uplift.
- If B24 is good, separately run a 2K/128 test before even considering explicit B32 consent. Never automatically search 32/64.
- Do not run 6K stress test as precondition. An observed 55s client timeout for a 6K prompt cannot alone prove deadlock, especially after measured 2K prefill took 90–110s.

## Certification and promotion
1. macOS Swift launch policy tests: 8/16/24/32 certification gates, explicit consent, shared pending and sticky SAFE4, inherited Build100 preference disabled, 32K-only.
2. Existing Build93/94/97/100 regression gates continue to pass. Full pinned Prism + signed-unmodified Xcode app iOS build, version 102 and distinct IPA identity.
3. True M5 iPad AB(A) 16/24/16 and long input, matching output, no crash or unsupported fallback.
4. Post-vision text survival, 1–3 images, SSE/UTF-8/JSON, 32K text context and long output survive regression.
5. Build100 remains experimental but rollback target, Build97 remains frozen source ancestor. Build102 must never be promoted based only on green CI.

## Important measurement limitation
Build100 `pending` marks a candidate launch before inference; normal user exit without a >=200-token input can be misclassified as an incomplete attempt. That issue belongs in isolated Build101 lifecycle work, not in this performance-only branch. On test device always complete a valid >=200-token text run before exit or explicitly acknowledge safe recovery if necessary.
