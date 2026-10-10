# RC1.26 Build 98 — M5 FA-vec single-IPA A/B lab

## Identity and isolation
- Base: Build97 successful commit `f88ed20ac320671c9308bb7c6b84a0288f08ead6`
- Branch: `lab-v1-rc1-26-build98-m5-fa-vec-ab`
- Prism source is pinned at `adfffbe41b2cabcd51fff326ab045662265062bb`.
- One unsigned IPA contains A0, A1, A2; **no three-IPA installation workflow**.
- All production model weights remain external. Build97 branch and pinned commit are unchanged.

## Target shape and algorithm
The native patch changes only the chosen `fa_vec_cfg_t.NE` after the pinned Prism `fa_vec_pick()` and before the existing pipeline selection. No attention math is rewritten.

Exact runtime guards: Metal GPU family 10, name `Apple M5 GPU`, Q4_0 K cache, `ne01 == 1`, `ne11 >= 1024`, `dk == dv == 256` and original `cfg.Q == 1`.

Arms:
- **A0**: no configuration override, original Prism decision
- **A1**: override `Q=1, NE=2` on the guarded shape only
- **A2**: override `Q=1, NE=4` on the guarded shape only

`NE` is elements per GPU thread, **not** the number of KV splits or a 4x parallelism promise. The existing Prism FA-vec split-workgroup and reduce implementation remains unchanged.

## Launch and rollback
The UI disclosure on the home screen selects **the NEXT complete app process launch**. On launch the app latches A0/A1/A2 through local-only process environment, then immediately resets the *next* selection to A0. It does not persist A1/A2 as a new default, including after a crash. Do not use app suspension as a full restart; quit the app process and reopen it.

No public API operation can set or alter the experiment arm. Existing authenticated GET `/debug/runtime` exposes `fa_vec_experiment` with both active and next arms and the one-time native decision trace; native trace is only created after a qualifying long-KV FA-vec operation. An absent trace is an explicit **NOT CONFIRMED** status, not evidence of a speed result.

## A/B device procedure
1. Download the unsigned Build98 IPA only from a **fully successful** GitHub Actions run, sign/install in the usual way. Keep Build97 IPA for reinstall rollback if needed.
2. Select the existing 27B PTQ1_0 GGUF, context **32768** (Q4 KV), and start OpenAI compatible API. Preserve the same Batch/uBatch and all runtime options for each arm. Recommended server max-output >=128.
3. Leave A0 selected; verify active A0. On Windows PowerShell 7:
   `$env:BONSAI_API_KEY = '<key shown inside iPad app>'`
   `pwsh -NoProfile -File .\tools\rc126_build98_fa_vec_arm.ps1 -ExpectedArm A0 -BaseUrl http://<iPad-IP>:8080/v1`
4. In the iPad home disclosure, schedule A1, fully quit app and reopen. Re-select model/start API if needed, re-check 32768 context and effective Batch; run script with `-ExpectedArm A1`. Repeat for A2.
5. A0 is automatically scheduled next on every candidate launch. Confirm the native trace reports matching `arm`, `dk=256`, `dv=256`, `kv_type=Q4_0`, `Q=1`, and `NE=2/4` on A1/A2.
6. Preserve the generated JSON evidence. Do NOT promote on the basis of a single run or without matching actual prompt/completion counts.

The script uses existing authenticated GET `/debug/runtime`, GET `/debug/prefill`, POST `/v1/chat/completions`. It asks for the API key on first use if `BONSAI_API_KEY` is unset and never writes it into the evidence.

## Evidence gate
- **CI**: static source contracts and real Xcode/Prism compilation; this does not certify GPU numerical correctness.
- **Discovery**: one A0/A1/A2 run each; stop if no native target trace or wrong effective Arm, crash, malformed output, or context mismatch.
- **Promotion candidate**: repeated interleaved A0/A1/A2 true-device comparisons, same prompt and measured input tokens, GPU temperature/readiness documented. Confirm deterministic tasks and numerical output behavior. Desired end-to-end Decode median benefit >=5% with no meaningful memory, correctness or stability loss. Small difference is INCONCLUSIVE.
- **Stop**: if gains are absent/unreliable, archive negative result; keep Build97. Do not change other kernels, memory scheduler, Vision, or KV layout to chase this target.

## Limitations
True Metal GPU per-kernel timings and direct small-tensor mathematical equivalence have not been certified in the macOS build workflow. This is an experiment build, not a production optimization. Remote API trace can verify which config was selected but cannot establish latency attribution to Attention vs PTQ1/GDN.
