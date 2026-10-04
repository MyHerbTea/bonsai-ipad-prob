# RC1.23.2 — Frozen Performance Baseline

Status: **FROZEN**

Frozen executable baseline:

- Version: RC1.23.2
- Build: 41
- Branch: `lab-v1-rc1-23-2-performance-session-reuse`
- Source commit: `990e8d6d90a660461fa14c4d391202efb2eb0bd5`
- Core C2-B implementation commit:
  `afe2c049fd0a559eda03a780ac79de080a18a1b5`
- Packaging CI: run #23 / `37183223825` — SUCCESS
- Accepted architecture: **single-sequence ON_DEVICE Vision-prefix state checkpoint**
- Rejected architectures:
  - C1 partial KV trim;
  - C2-A two-sequence `n_seq_max=2`.

## Frozen behavior

The build-41 baseline keeps:

- `n_seq_max=1`;
- sequence 0 as the only llama work sequence;
- Prism `llama_state_seq_get_size_ext`,
  `llama_state_seq_get_data_ext` and
  `llama_state_seq_set_data_ext`;
- `LLAMA_STATE_SEQ_FLAGS_ON_DEVICE`;
- reuse identity bound to image cache identity + system prompt;
- request-specific suffix/generation cleanup;
- text/failure/unload invalidation;
- RC1.23.1 API and error semantics;
- RC1.22.5 MLX hard graph-cut;
- BVCACHE1 binary contract;
- 5120 projected embedding width.

The UI switch remains default OFF. Turning
`Vision Prefix KV Reuse` ON enables the validated warm path.

## Target-device certification

Device:

- iPad Pro M5-class
- 12 GB physical memory
- iPadOS 27.0.1

Controlled build-41 results:

- first image request: 27157.4 ms;
- repeated identical image request: 18454.9 ms;
- end-to-end improvement: 32.04%;
- warm 27B prefill: 2.514 s;
- warm prefix prefill: 0.000 s;
- warm image prefill: 0.000 s;
- warm suffix prefill: 2.514 s;
- reuse: HIT;
- retained: true;
- exact text recovery: PASS;
- MLX peak: 144 MiB.

Build-40 OFF comparison:

- 27B prefill: 10.280 s;
- prefix: 1.662 s;
- image: 6.028 s;
- suffix: 2.590 s.

## Isolation certification

- same image + different question: PASS;
- previous suffix leakage: not observed;
- previous assistant-output leakage: not observed;
- text request invalidates Vision checkpoint: PASS;
- different image forces MISS: PASS;
- repeated new image becomes HIT: PASS;
- checkpoint rollover to new image: PASS.

## Stability certification

10-request warm-hit soak:

- 10/10 HTTP 200;
- no crash;
- final HIT retained=true;
- prefix/image prefill still 0.000/0.000 s;
- MLX peak remained 144 MiB;
- average 21679.6 ms;
- min 17916.4 ms;
- max 26326.2 ms.

Long-soak throughput degradation was observed, but the checkpoint continued to
behave correctly. A later same-session probe recovered to 17970.4 ms on the
second image request with 2.439 s prefill and 29.70% end-to-end improvement.
Because the API request counter did not reset, this is explicitly **not**
recorded as a clean-restart certification.

## Non-regression rule

Future versions must not claim improvement if they lose any of the following:

1. API startup stability;
2. `n_seq_max=1` compatibility on the target device;
3. correct MISS -> checkpoint -> HIT behavior;
4. zero prefix/image prefill on a true same-image warm HIT;
5. question/suffix isolation;
6. text invalidation;
7. different-image isolation;
8. text recovery;
9. RC1.23.1 multimodal/error semantics;
10. RC1.22.5 hard graph-cut behavior;
11. bounded memory/no crash under the 10-hit soak.

Any future optimization must be compared against this build-41 frozen
baseline, not against C1 or C2-A.
