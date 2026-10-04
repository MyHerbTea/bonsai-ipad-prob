# RC1.23.4 FROZEN GENERATION TELEMETRY BASELINE

Status: **FROZEN**
Frozen build: **46**
Frozen executable source: `4c0a453339350c0c915578a46a15d4235ab0ff99`
Parent baseline: **RC1.23.3 Build 45 FROZEN**

## Release evidence

- Validation branch: `lab-v1-rc1-23-4-generation-decode-efficiency`
- GitHub Actions run: **#37**
- Run ID: `37202037952`
- CI conclusion: **SUCCESS**
- Artifact: `BonsaiLab-iPad-v1-RC1.23.3-Build46-Generation-Telemetry-Candidate`
- Artifact ID: `11302983359`
- Artifact size: **7,449,891 bytes**
- Note: the artifact name retains the RC1.23.3 workflow prefix; the executable is RC1.23.4 Build 46. This is a naming legacy only.

## True-device acceptance environment

- Device: **iPad Pro M5**
- Physical memory: **12 GB class** (`11524 MiB` reported)
- OS: **iPadOS 27.0.1**
- Main model: `Ternary-Bonsai-2-27B-PTQ1_0.gguf`
- Vision tower: `Bonsai-2-27B-vision_tower-fp16.safetensors`
- API model id: `bonsai-2-27b-local`

## Frozen runtime

The RC1.23.3 runtime decision remains unchanged:

- runtime profile: **Accelerated**
- Safe remains the compatibility fallback
- Flash-only remains rejected
- `flash_attention=true`
- `offload_kqv=true`
- `op_offload=true`
- `kv_unified=true`
- `load_mode=mmap`
- `api_context=512`
- `api_batch=8`
- `api_ubatch=8`
- `n_seq_max=1`
- Vision Prefix KV reuse enabled

RC1.23.4 does **not** redefine the runtime profile.

## What Build 46 freezes

Build 46 freezes an evidence-backed generation telemetry contract.

For successful text and vision requests the diagnostic path exposes:

- `requested_max_tokens`
- `effective_max_tokens`
- `completion_tokens`
- `termination_reason=eog|length`
- `finish_reason=stop|length`
- `ttft_ms`
- `prefill_ms` where applicable
- `decode_ms`
- `tokens_per_second`
- `total_ms`

The decoder is the source of truth for termination provenance:

- decoder EOG -> `termination_reason=eog` -> OpenAI `finish_reason=stop`
- budget exhaustion -> `termination_reason=length` -> OpenAI `finish_reason=length`

The old token-count-only finish-reason inference is not the frozen behavior.

## True-device text matrix

Controlled text prompt:

`Reply with one concise sentence describing why the sky appears blue.`

Observed Build 46 behavior:

| Requested | Effective | Completion | Termination | Finish |
|---:|---:|---:|---|---|
| 32 | 32 | 29 | eog | stop |
| 64 | 64 | 29 | eog | stop |
| 128 | 128 | 29 | eog | stop |

Conclusion:

- max completion tokens are a ceiling, not a forced exact length;
- normal text EOG behavior is correct;
- increasing the requested budget does not extend an already-complete answer.

## Vision EOG control

ASCII-only controlled prompt:

`Describe the person, the dog, and the background in this image using concise bullet points.`

Observed warm-HIT results:

| Requested | Effective | Completion | Termination | Finish | Decode throughput |
|---:|---:|---:|---|---|---:|
| 128 | 128 | 115 | eog | stop | 13.516 tok/s |
| 256 | 256 | 115 | eog | stop | 12.808 tok/s |

Both requests produced the same complete answer.

Conclusion:

- Vision generation can naturally reach EOG;
- there is no evidence of a generic Vision EOG/decoder termination defect;
- 128/256 are maximum budgets, not mandatory generation lengths.

## UTF-8 PowerShell 5.1 acceptance

An earlier Windows PowerShell 5.1 test harness corrupted the Chinese prompt and response encoding. That contamination produced question-mark prompt text and mojibake and therefore was not valid evidence about model termination.

The frozen probe `tools/rc1234_generation_probe.ps1` now:

- is ASCII-only at source level;
- reconstructs its default Chinese prompt from Base64 UTF-8 bytes;
- sends `Content-Type: application/json; charset=utf-8`;
- explicitly sends UTF-8 JSON bytes;
- explicitly decodes HTTP response bytes as UTF-8;
- sets console output encoding to UTF-8;
- does not depend on `Invoke-RestMethod` encoding inference.

The final Windows PowerShell 5.1 smoke test displayed normal Chinese text and no longer produced `????` or mojibake.

## Final UTF-8 Chinese vision smoke

Prompt:

`请描述这张图片中的人物、动物和背景。`

Observed behavior:

| Requested | Effective | Completion | Termination | Finish |
|---:|---:|---:|---|---|
| 32 | 32 | 32 | length | length |
| 64 | 64 | 64 | length | length |
| 128 | 128 | 128 | length | length |

This does **not** contradict the ASCII EOG control. The Chinese descriptive prompt requests a broader answer and is visibly truncated at the tested budgets. The concise English control naturally terminates at 115 tokens.

Frozen conclusion:

> Output length is prompt-dependent. Do not treat a length-terminated descriptive answer as evidence of a broken EOG path.

## Decode performance conclusion

Build 46 telemetry separates token-generation cost from other request costs.

Representative true-device observations:

- text decode throughput: roughly **11.5-12.0 tok/s**;
- warm Vision decode throughput: roughly **11.4-13.5 tok/s**;
- a 128-token Vision completion consumes about **11 s** of decode at approximately 11.6 tok/s.

Therefore the current evidence does not support the claim that Vision decode throughput is catastrophically slower than text decode throughput.

Long Vision E2E latency is often explained by:

1. suffix/question prefill;
2. the actual number of generated completion tokens.

## Frozen C2-B non-regression

The following RC1.23.2/RC1.23.3 invariants remain frozen:

1. `n_seq_max=1`.
2. Same-sequence ON_DEVICE C2-B state checkpoint save/restore.
3. Reuse remains `HIT + retained=true`.
4. On a warm HIT, prefix/image prefill remains zero.
5. Reuse identity/invalidation semantics remain unchanged.
6. Vision Prefix KV reuse remains enabled.
7. Projection width remains 5120.
8. RC1.22.5 MLX hard graph-cut behavior remains unchanged.
9. RC1.23.1 OpenAI multimodal/error behavior remains unchanged.
10. RC1.23.3 Accelerated runtime remains the default and Safe remains fallback.
11. Privacy diagnostics continue excluding API keys, raw image/base64, prompt text, and assistant output.

## Rejected or disproven paths

Do not reopen these without new regression evidence:

- C1 partial KV trim;
- C2-A multi-sequence / `n_seq_max=2`;
- Flash-only runtime as the performance product default;
- generic "Vision cannot EOG" hypothesis;
- automatic reduction of 128/256 output budgets solely for speed;
- treating PowerShell 5.1 implicit encoding as valid Unicode-model evidence;
- assuming Vision latency means Vision token decode is intrinsically much slower than text.

## Known compatibility / product gaps

These are not Build 46 regressions and are not silently fixed by this freeze:

1. Request parsing accepts a larger range than the current product execution ceiling; effective API generation is capped at 256 in the product layer.
2. OpenAI `stop` sequences are not yet implemented as a request-level stop-sequence feature.
3. The Build 46 artifact/workflow name still carries an RC1.23.3 prefix.
4. Prompt style materially changes prompt tokens, suffix prefill, completion length, and E2E latency. Performance comparisons must use controlled prompts.

## Immutability rule

RC1.23.4 Build 46 is the frozen Generation Telemetry executable baseline.

Future work must not silently change:

- Accelerated runtime selection;
- Safe fallback semantics;
- C2-B implementation;
- `n_seq_max=1`;
- Vision Prefix KV reuse semantics;
- Build 46 telemetry field meanings;
- decoder-provenance finish-reason mapping;
- PowerShell 5.1 explicit UTF-8 probe behavior.

Any such change requires a separately named stage and explicit regression evidence.

## Next stage

Proceed to:

**RC1.23.5 / Build 47 — TTFT & Suffix Prefill Efficiency**

The next stage must profile first, choose exactly one optimization hypothesis from evidence, and then perform a controlled Build 46 vs Build 47 true-device A/B.
