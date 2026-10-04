# RC1.23.2 — Multimodal Performance & Session Reuse

Status: **FROZEN PERFORMANCE BASELINE — BUILD 41 / PHASE C2-B**

Base: `a032634d992f3b2edf0b3665e9b381ee4d6c06cf`  
Parent behavior: RC1.23.1 OpenAI Multimodal API candidate.

## Goal

Reduce end-to-end latency for repeated local API requests without changing the
validated multimodal semantics.

The optimization order is deliberately:

1. observe,
2. prove a bottleneck,
3. optimize one boundary,
4. compare,
5. keep or revert.

No performance gain may be claimed from CI alone.

## Frozen boundaries

RC1.23.2 must not change:

- RC1.22.5 MLX Vision hard graph-cut execution;
- per-layer safetensors reopen;
- CPU copy/rebuild graph cut;
- projected embedding dimension `5120`;
- BVCACHE1 binary format or native vision injection math;
- RC1.23.1 single-image request/error semantics;
- text API response envelopes or SSE contract;
- explicit failure instead of silent text fallback.

## Phase A — Performance observability

**Implemented first. No inference behavior change.**

Each API request stores one compact last-request snapshot:

- request id;
- route: text / vision;
- streaming flag;
- success or failed/interrupted;
- total request milliseconds;
- image temp-file write milliseconds;
- MLX vision encode milliseconds;
- sidecar-reported encode milliseconds;
- projected-cache write milliseconds;
- 27B vision prefill milliseconds;
- text TTFT milliseconds;
- decode milliseconds;
- tokens/second;
- prompt/completion token counts;
- visual rows;
- projection dimension;
- grid;
- M-RoPE `n_pos`;
- image ordering;
- cache reuse state;
- last stage on failure.

The same data is surfaced through:

`高级与诊断 → 刷新并复制完整诊断 → [LAST API REQUEST PERFORMANCE]`

The diagnostic snapshot remains privacy bounded: no API key, raw image,
base64, prompt body, or assistant response body.

## Phase B — Vision embedding cache reuse

Status: **DEFERRED / LOWER PRIORITY AFTER PHASE A DEVICE EVIDENCE**.

Phase A measured Vision encode + cache write at only about 0.24 s, while
27B multimodal prefill was about 9.63 s. Phase B remains a valid follow-up
optimization, but it is not the primary RC1.23.2 latency target.

Candidate design:

- compute the existing content-addressed BVCACHE1 identity before MLX encode;
- validate an existing cache using the frozen native cache validator;
- on a valid hit, skip MLX Vision encode and projected-cache rewrite;
- preserve all RC1.23.1 request/error semantics;
- record `cache_reuse=hit|miss`;
- fall back to the existing RC1.23.1 path on a miss.

This phase requires real-device A/B evidence before being accepted.

## Phase C — 27B context / KV reuse

Status: **PRIMARY OPTIMIZATION TRACK**.

Phase A device evidence justified advancing this phase ahead of Phase B because
27B multimodal prefill dominates the measured repeated-image latency.

Any reuse must prove:

- no cross-request prompt leakage;
- no historical-image leakage;
- exact system/user boundary correctness;
- cleanup after failures;
- text API recovery;
- bounded memory growth;
- same response semantics as the frozen baseline.

A warm-path optimization is rejected if it relies on hidden stale KV state.

## CI gate

Every candidate must pass:

- inherited RC1.20.x / RC1.21.x / RC1.22.5 invariants;
- RC1.23.1 multimodal parser/source contracts;
- RC1.23.2 observability source contracts;
- Swift syntax preflight;
- Xcode project generation;
- full Release iOS build;
- Prism multimodal symbol verification;
- unsigned IPA packaging.

## Real-device gate

Status: **COMPLETED — 2026-10-04**.

The target-device program completed controlled performance, isolation and
stability testing on iPadOS 27.0.1 with the 12 GB iPad Pro M5-class device.

The accepted path is Phase C2-B. Phase C1 and C2-A remain documented as
rejected experiments and must not be reintroduced into the frozen baseline.


## Phase A real-device evidence — 2026-10-04

Device: iPad Pro M5 class, 12 GB, iPadOS 27.0.1.  
Build: 38 observability candidate.

Last successful vision request:

- total internal request: 12099.239 ms;
- MLX vision encode: 241.599 ms;
- sidecar-reported encode: 219.156 ms;
- BVCACHE1 write: 1.803 ms;
- 27B prefill: 9629.370 ms;
- decode: 2220.502 ms;
- decode rate: 8.557 tok/s;
- prompt tokens: 86;
- completion tokens: 19;
- visual rows: 54 x 5120;
- grid: 9x6;
- M-RoPE n_pos: 9.

Windows end-to-end measurements:

- text first: 4322.9 ms;
- text repeat: 4422.4 ms;
- first image: 12761.0 ms;
- same-image repeat: 18415.1 ms;
- post-failure text recovery: 3873.8 ms;
- final vision: 12248.1 ms.

Safety/semantics remained intact:

- stale historical image binding -> HTTP 400 invalid_content_part;
- invalid base64 -> HTTP 400 invalid_image_data;
- text request after failure -> HTTP 200;
- image-grounded output remained correct.

### Decision

Do **not** prioritize projected-embedding cache reuse as the main optimization.
The measured MLX encode + cache write cost is only about 0.24 s, while the
27B multimodal prefill alone is about 9.63 s.

The next optimization target is therefore **Vision-prefix KV reuse**.

## Phase C1 — Experimental Vision-prefix KV reuse

Status: **DEVICE REJECTED — SAFE FALLBACK CONFIRMED**

Design:

- same image is identified by the existing content-addressed BVCACHE1 path;
- same system prompt is part of the reuse identity;
- after a successful request, keep only the KV corresponding to
  `prefix + image`;
- remove the request-specific suffix and generated continuation;
- on the next matching request, decode only the new question suffix;
- any text request, model unload, or request failure invalidates the reuse state;
- if partial KV removal is unsupported, clear the entire llama memory and
  automatically fall back to the RC1.23.1 path;
- BVCACHE1 format, Vision Tower math, projected embedding width and API
  semantics remain unchanged.

The experiment is controlled by:

`高级与诊断 -> 实验：Vision Prefix KV Reuse`

Default: **OFF**.

Diagnostics include:

- prefix_reuse_enabled;
- prefix_reuse_hit;
- prefix_retained;
- prefix_positions;
- prefix_text_ms;
- image_prefill_ms;
- suffix_prefill_ms.

### Phase C1 real-device result — 2026-10-04

Build 39 controlled OFF/ON evidence:

- OFF repeated-image request remained a full MISS;
- ON repeated-image request was also a MISS;
- ON diagnostic reported `prefix_retained=false`;
- OFF 27B prefill: about 10.318 s;
- ON 27B prefill: about 10.400 s;
- ON same-image request #2 was 8.31% slower end-to-end than request #1;
- Vision output remained semantically correct;
- MLX peak remained 144 MiB;
- post-vision text recovery returned `TEXT_RECOVERY_OK`.

Root cause was confirmed in the C1 implementation: post-generation retention
depended on partial `llama_memory_seq_rm(..., prefix_positions, -1)`. The
pinned Prism runtime explicitly permits partial removal to fail. On device that
operation returned unsupported, so Bonsai cleared the full KV memory and
correctly fell back to the RC1.23.1 behavior.

### Phase C1 decision

**NO-GO for the partial-trim design.**

The experiment failed safely: no semantic regression, stale-image leakage,
text-recovery failure, crash, or observed MLX memory regression was introduced.

## Phase C2-A — Sequence checkpoint Vision-prefix KV reuse

Status: **DEVICE REJECTED — API STARTUP CRASH**.

C2-A replaces C1 partial trimming with two llama sequences:

- sequence 0: request working sequence;
- sequence 1: retained `prefix + image` checkpoint;
- first matching vision request copies the completed prefix+image KV from
  sequence 0 into sequence 1 before suffix decode;
- after generation, the whole sequence 0 is removed;
- the whole retained sequence 1 remains as the checkpoint;
- the next same-image + same-system request copies sequence 1 back to
  sequence 0 and decodes only the new suffix;
- whole-sequence removal is used instead of unsupported partial removal;
- the experimental context uses `n_seq_max=2`; the default-OFF baseline
  remains `n_seq_max=1`;
- text request, request failure, model unload, image identity change, or system
  prompt identity change still invalidates reuse state;
- if the experimental toggle is enabled only after a one-sequence context was
  already created, the optimization stays disabled until a clean restart.

Pinned Prism support verified for C2-A:

- `llama_memory_seq_cp`;
- `llama_memory_seq_keep`;
- whole-sequence `llama_memory_seq_rm`;
- sequence position inspection.

Commit implementing C2-A:

`f32b7bb7fd41bbe07a90e678b8d4d636095adb7c`

GitHub Actions run #20 / `37180140338`: **SUCCESS**.

### Phase C2-A real-device result — 2026-10-04

Build 40 OFF remained healthy:

- API startup succeeded;
- repeated image requests returned HTTP 200;
- 27B prefill was about 10.280 s;
- prefix reuse remained MISS with retained=false, as expected while disabled;
- MLX peak remained 144 MiB;
- post-vision text recovery returned `TEXT_RECOVERY_OK`.

With the experimental toggle enabled before API startup, the application
terminated while the API runtime was creating the 27B context, before any
multimodal request or checkpoint operation ran.

The controlled code difference at that boundary was the C2-A requirement to
create the experimental context with `n_seq_max=2` instead of the validated
single-sequence `n_seq_max=1`.

### Phase C2-A decision

**NO-GO.**

C2-A is rejected because it regressed API runtime startup on the target device.
The default-OFF path remained healthy, so there is no evidence of a baseline
regression.

## Phase C2-B — Single-sequence ON_DEVICE state checkpoint

Status: **ACCEPTED AND FROZEN — BUILD 41**.

C2-B removes the C2-A multi-sequence requirement and restores the context shape
that already passed build 40 OFF testing:

- `n_seq_max=1` for both normal and experimental runtime creation;
- sequence 0 remains the only working sequence;
- after prefix + image prefill, the sequence state is snapshotted with pinned
  Prism `llama_state_seq_get_size_ext` and
  `llama_state_seq_get_data_ext`;
- `LLAMA_STATE_SEQ_FLAGS_ON_DEVICE` keeps KV tensor data in Prism-managed
  backend buffers while only compact state metadata is retained in host memory;
- request-specific suffix and generated continuation are cleared after the
  request;
- on the next same-image + same-system request, the saved state is restored to
  sequence 0 with `llama_state_seq_set_data_ext`, then only the new suffix is
  prefetched;
- logical misses, failures, unloads and identity changes invalidate the
  checkpoint;
- C2-A `llama_memory_seq_cp`, `llama_memory_seq_keep`, sequence 1 and
  `n_seq_max=2` are forbidden by the RC1.23.2 contract test.

C2-B implementation commit:

`afe2c049fd0a559eda03a780ac79de080a18a1b5`

GitHub Actions run #22 / `37182779661`: **SUCCESS**.

### Phase C2-B real-device acceptance — 2026-10-04

Build 41 passed the controlled device gate.

Primary performance run:

- API startup with Vision Prefix KV Reuse enabled: PASS;
- image request #1: HTTP 200, 27157.4 ms end-to-end;
- image request #2: HTTP 200, 18454.9 ms end-to-end;
- measured end-to-end improvement: 32.04%;
- second-request 27B prefill: 2.514 s;
- second-request prefix prefill: 0.000 s;
- second-request image prefill: 0.000 s;
- second-request suffix prefill: 2.514 s;
- second-request reuse state: HIT, retained=true;
- text recovery: exact `TEXT_RECOVERY_OK`;
- MLX peak: 144 MiB.

The build 40 OFF comparison was a full MISS with:

- 27B prefill: 10.280 s;
- prefix: 1.662 s;
- image: 6.028 s;
- suffix: 2.590 s.

Therefore the repeated-image C2-B path removed approximately 7.77 seconds of
prefix + image prefill in the controlled build-41 run.

### Isolation certification

All required reuse boundaries passed:

1. **Same image, different question — PASS**
   - second request remained HIT and retained=true;
   - prefix and image prefill remained 0.000 s;
   - the new question requested only the animal identity;
   - output was `Golden Retriever`;
   - previous question/assistant suffix leakage was not observed.

2. **Text request invalidation — PASS**
   - text returned exact `TEXT_INVALIDATE_OK`;
   - the following same-image Vision request correctly became MISS;
   - retained=true after rebuilding the checkpoint;
   - full prefill returned: prefix 1.644 s, image 5.813 s,
     suffix 2.498 s, total 9.971 s.

3. **Different-image isolation — PASS**
   - image A SHA256:
     `EBDC2AED7527E7C514D2A8C26B1E3ACD8C03AFC0C7D716BA414C743288BCBEBA`;
   - horizontally flipped image B SHA256:
     `24BCC634A19BA63EB302D77B0F187BE508807E69D2447C1EFC38E1EF07B76529`;
   - image B correctly produced MISS, retained=true;
   - full prefill was 9.992 s.

4. **New-image repeat — PASS**
   - repeated image B produced HIT, retained=true;
   - prefix and image prefill were 0.000 s;
   - suffix/total prefill was 2.438 s;
   - end-to-end time was 17992.7 ms.

### Stability certification

A 10-request repeated-hit soak completed:

- 10/10 requests returned HTTP 200;
- no crash occurred;
- final checkpoint remained HIT and retained=true;
- final prefix and image prefill remained 0.000 s;
- MLX peak remained 144 MiB;
- end-to-end average: 21679.6 ms;
- minimum: 17916.4 ms;
- maximum: 26326.2 ms.

The later soak requests showed lower 27B throughput. The final soak request had
3.419 s suffix prefill and 6.129 tok/s decode throughput, but checkpoint
correctness did not regress.

A subsequent **same-session** recovery probe (the API request counter advanced
from 19 to 22, so this must not be described as a proven clean restart) again
produced:

- second image request: 17970.4 ms;
- end-to-end improvement: 29.70%;
- 27B prefill: 2.439 s;
- prefix/image prefill: 0.000 / 0.000 s;
- HIT, retained=true;
- exact `TEXT_RECOVERY_OK`.

This recovery without a confirmed API-session reset is evidence against
cumulative C2-B checkpoint leakage as the cause of the later soak slowdown.
The slowdown is retained as an observed runtime/device throughput effect, not
as a correctness failure.

### Phase C2-B decision

**ACCEPTED.**

RC1.23.2 freezes build 41 as the validated performance baseline. Future work
must preserve:

- single-sequence `n_seq_max=1`;
- C2-B ON_DEVICE sequence-state checkpoint semantics;
- exact image/system reuse identity;
- text/failure/unload invalidation;
- zero prefix/image prefill on a true warm HIT;
- RC1.23.1 API/error semantics;
- RC1.22.5 MLX hard graph-cut behavior;
- BVCACHE1 format and 5120 projection width.

The experimental toggle remains default OFF in the frozen build. Enabling it
activates the validated C2-B path.

Executable baseline source commit:

`990e8d6d90a660461fa14c4d391202efb2eb0bd5`

Build-41 packaging CI:

GitHub Actions run #23 / `37183223825`: **SUCCESS**.
