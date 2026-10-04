# RC1.24.0 Build 55 — Sustained Decode Profiling

Status: **INSTRUMENTATION-ONLY CANDIDATE**

Parent baseline:
- RC1.23.6 Build 54
- device-certified Production Stop / Resume
- resident runtime preservation PASS
- OpenAI Vision API PASS
- Vision Prefix KV reuse PASS
- cross-image cache isolation PASS
- OFF/ON prefix reuse A/B PASS

## Problem

Build 54 device evidence showed repeatable decode throughput degradation during
continuous requests. Early requests could decode near 12–13 tok/s while later
requests settled around 7–8 tok/s even when iPadOS continued to report thermal
state `nominal`.

RC1.24.0 Build 55 does **not** attempt to optimize or change inference.
Its only purpose is to collect enough per-request evidence to identify where
the sustained decode slowdown comes from.

## Frozen inference behavior

Build 55 preserves the Build 54 runtime path:
- API context = 512
- batch = 8
- ubatch = 8
- Accelerated profile
- Flash Attention enabled in Accelerated mode
- KQV offload enabled
- op offload enabled
- unified KV enabled
- mmap model loading
- existing text generation path unchanged
- existing MLX Live Vision Injection path unchanged
- existing Vision Prefix KV reuse behavior unchanged
- product Stop / Resume behavior unchanged

No performance optimization belongs in Build 55.

## New diagnostics

Each API request records:
- request ordinal
- session elapsed time
- idle gap
- TTFT
- decode time
- tokens/sec
- thermal state start/end
- Low Power Mode start/end
- process CPU user time delta
- process CPU system time delta
- process CPU total time delta
- estimated process CPU percentage over request wall time
- active processor count
- app scene phase start/end
- resource snapshot at request start and end
- available-memory delta
- resident-memory delta
- physical-footprint delta
- virtual-memory delta
- Metal allocated-memory delta
- Metal recommended-memory delta

The existing end-of-request fields remain for backward compatibility.

## Device experiment sequence

### Phase A — Text-only sustained decode

Use one fixed prompt and fixed generation settings:
- no image
- max_tokens = 128
- context = 512
- batch = 8
- ubatch = 8
- Accelerated profile
- ten consecutive requests
- keep Bonsai foregrounded

Goal: determine whether decode degradation exists without Vision.

### Phase B — Vision sustained decode

Use one fixed image and fixed prompt:
- same runtime settings as Phase A
- Vision Prefix KV reuse ON
- ten consecutive requests
- keep Bonsai foregrounded

Goal: compare text-only and Vision decode curves.

### Phase C — Recovery matrix

After throughput has fallen, test one recovery action at a time:
1. listener Stop / Resume while preserving resident runtime;
2. full engine unload / reload;
3. 60-second idle;
4. foreground/background lifecycle only if explicitly testing full-release behavior.

The action that restores the original decode rate identifies the layer whose
state must be investigated next.

## Acceptance

Build 55 PASS requires:
- source contracts pass;
- Swift parser passes;
- Xcode Release build passes;
- unsigned IPA packages successfully;
- Build 54 inference/runtime contracts remain green;
- new profiling fields appear in diagnostic output;
- no intentional change to generation semantics.

Build 55 is not allowed to claim a performance fix.
