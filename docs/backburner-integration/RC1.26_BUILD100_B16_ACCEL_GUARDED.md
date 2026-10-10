# Build100 — Guarded 32K Batch16 Prefill Acceleration (experimental)

Status: **SOURCE CANDIDATE / REAL-DEVICE CERTIFICATION REQUIRED**

## Frozen source and protected scope
- Parent: Build97 source commit `f88ed20ac320671c9308bb7c6b84a0288f08ead6`.
- Isolated branch: `lab-v1-rc1-26-build100-b16-accel-guarded`.
- Prism commit stays pinned at `adfffbe41b2cabcd51fff326ab045662265062bb`; no M5 FA-vec NE adjustment.
- Does **not** inherit Build99 APPEND token-ledger code, failed reuse route, or any other kernel experiment.
- Vision (1–3 images), OpenAI API semantics, 32K Q4_0, selected model, long output budget and recovery are frozen functional boundaries.

## Grounded speed signal from user real-device evidence
Fixed 32,768 context, KV Q4_0, 939 actual input tokens / 32 generated, identical source and output SHA256, thermal nominal:
| Test sequence | Effective batch/uBatch | Prefill (s) | End-to-end (s) |
|---|---|---:|---:|
| B8-1 | 8/8 | 121.61 | 125.88 |
| B16 | 16/16 | 35.26 | 39.63 |
| B8-2 | 8/8 | 124.14 | 128.51 |

B8 mean Prefill = 122.875 seconds, B16 = 35.26 seconds, speed ratio = 3.485. This is a **strong scoped candidate signal**, not stable product certification. B16 only one successful run in the ABA sequence. Do not claim universal speedups, GPU occupancy or memory peak safety from the data.

## Build100 implementation
Build94's pre-context safety state machine is retained. Build100 **does not automatically enable B16 for new installations**. A new opt-in toggle (UserDefaults `BonsaiBuild100PreferGuardedB16`) is OFF by default.

When the app creates an *exact 32768* token context:
1. Previous incomplete B16 candidate or explicit startup failure: select sticky SAFE4 and disable B16 preference.
2. Inherited Build93 sticky fallback: likewise SAFE4.
3. User opts in and existing Build94 `confirmed_candidate16=true` and `baseline8_completed=true`: choose B16 as recurring guarded candidate, set pending marker before context load.
4. Otherwise B8 baseline; any unqualified preference is automatically cleared.
5. The effective selected shape is written to both `RuntimeConfig.batch` and `RuntimeConfig.ubatch` **before** llama context creation. Old Phase2D/2E/2F latches cannot silently cap an elected B16 to B8.
6. A successful text request of >=200 input tokens clears the candidate pending marker. A short/aborted session does not certify the trial; next launch reverts to SAFE4 unless deliberately recovered.
7. A manual B8 scheduling request disables recurring B16 preference. The server refuses attempts to bypass fallback without explicit recovery acknowledgement.
8. 16K and other context sizes keep the inherited policy.

No mid-flight retry from a crashed llama context; no guessed thermal or memory threshold selector; no invented performance uplift.

## CI and promotion gates
- macOS Swift lifecycle tests: base qualification, repeated opt-in candidate, sticky SAFE4 on incomplete/start failure, recovery acknowledgement, explicit B8 exit, wrong-context isolation.
- Build100 static assertions and inherited Build93/Build94/Build97 API/Vision tests.
- Full unmodified Prism XCFramework and Xcode compilation, distinct Build100 IPA identity.
- True iPad ABAB: existing B8 → B16 → B8 evidence; obtain independent B16 repeat before claiming repeatability.
- Fixed-prompt 2K Prefill and 128 output tokens; additionally smoke 4K input or 256 output only if thermal/memory safe.
- 1–3 image follow-up + post-vision text survival, stream/non-stream, SSE/UTF-8/JSON.
- Cold launch/relaunch, candidate incomplete shutdown, intentional SAFE4 recovery, 32K memory headroom/thermal.
- Require no regressions and a real speed benefit before suggesting default B16 for non-opted-in users.

## Real-device use
1. Install experimental Build100 (not stable).
2. Confirm selected model and 32768 Context; first read `GET /debug/build94/launch` and `GET /debug/prefill`.
3. If Build94 eligibility is present, toggle **Build 100 · 32K 推理加速实验 / 下次完整启动优先使用认证过的 Batch16/16**.
4. Fully terminate iPad app process (not merely stop API), reopen and start LAN API.
5. Assert `/debug/build94/launch`: `active_arm=CANDIDATE16`, `active_batch=16`, `active_ubatch=16`, `preferred_16_enabled=true`, and no fallback.
6. Run a >=200 input token text request, verify `pending=false`, `confirmed_candidate16=true`, compare Prefill/TTFT and hash, check memory and temperature.
7. On any discrepancy, disable preference and use deliberate safe B8/safe4 recovery path; do not loop a crashing candidate.

## Why next work is focused
Threefold Prefill improvement was observed by changing the batch shape, not by APPEND reuse or NE tuning. We will prioritize certifying this benefit and preserving cold-start/vision/long-output correctness. Once stable, a separate profiling study can determine whether GPU occupancy, launch overhead or graph shape explains the difference.
