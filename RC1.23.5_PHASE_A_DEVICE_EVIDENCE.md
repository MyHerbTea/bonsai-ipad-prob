# RC1.23.5 Phase A — True-Device Suffix Prefill Profiling Evidence

Status: **PASS — BATCHED PREFILL HYPOTHESIS REJECTED**

Parent executable: RC1.23.5 Build 47
Validated head: `9184d4723dbf6fe9feb36d2ad3677f45d34430a6`
CI: #40 / `37208426395` / SUCCESS
Device: iPad Pro M5 / iPadOS 27.0.1 / 11524 MiB physical memory
Runtime: Accelerated / API ctx 512 / batch 8 / ubatch 8 / n_seq_max 1

## Controlled test

The Phase A true-device matrix used the same image, model, runtime, output budget,
and reasoning mode.

Group A:
- prompt: `Describe the person, the dog, and the background in this image using concise bullet points.`
- max completion tokens: 128
- one seed request followed by six warm Prefix KV HIT requests

Group B:
- prompt: `请描述这张图片中的人物、动物和背景。`
- max completion tokens: 128
- three warm Prefix KV HIT requests

## Group A warm-HIT batching

All six warm concise requests had the same native suffix-prefill structure:

- suffix tokens: **29**
- suffix decode calls: **4**
- batch capacity: **8**
- ubatch capacity: **8**
- last batch tokens: **5**
- batch packing utilization: **0.9062 / 90.62%**

This is the expected packing for 29 tokens with an 8-token batch:

```text
ceil(29 / 8) = 4 calls
capacity = 4 * 8 = 32 token slots
utilization = 29 / 32 = 90.625%
```

There is no evidence of substantial fragmentation or repeated tiny decode calls.

## Group A warm-HIT latency statistics

Six warm requests:

| Metric | Mean | Median | Min | Max |
|---|---:|---:|---:|---:|
| total_ms | 15085.782 | 15130.612 | 11843.060 | 18598.491 |
| suffix_prefill_ms | 2955.331 | 2915.842 | 2438.396 | 3521.740 |
| suffix_ms_per_decode_call | 738.833 | 728.961 | 609.599 | 880.435 |
| decode_ms | 11825.608 | 11911.700 | 9061.584 | 14881.027 |
| decode TPS | 10.080 | 9.743 | 7.728 | 12.691 |

The first three warm requests versus the last three warm requests:

| Metric | First 3 mean | Last 3 mean | Delta |
|---|---:|---:|---:|
| total_ms | 12576.930 | 17594.633 | +39.90% |
| suffix_prefill_ms | 2520.384 | 3390.277 | +34.51% |
| suffix_ms_per_decode_call | 630.096 | 847.569 | +34.51% |
| decode_ms | 9743.697 | 13907.519 | +42.73% |
| decode TPS | 11.868 | 8.293 | -30.13% |

During this slowdown the suffix token count, decode-call count, batch capacity,
and packing utilization remained unchanged.

Therefore the slowdown cannot be explained by deteriorating batch packing.

## Group B warm-HIT batching

All three Chinese descriptive requests had:

- suffix tokens: **22**
- suffix decode calls: **3**
- batch capacity: **8**
- ubatch capacity: **8**
- last batch tokens: **6**
- batch packing utilization: **0.9167 / 91.67%**

Again, the suffix loop is densely packed.

## Resource / stability observations

During the final request:

- Prefix reuse: HIT
- Prefix retained: true
- prefix text prefill: 0 ms
- image prefill: 0 ms
- Metal allocated: about 6110 MiB
- available memory: about 4467 MiB
- physical footprint: about 652 MiB
- public thermal state: nominal
- Low Power Mode: false

No C2-B regression or memory accumulation was observed.

## Phase A decision

### Candidate A — Batched suffix prefill

**REJECTED for RC1.23.5.**

Reason:

- observed packing utilization is already about 90.6–91.7%;
- decode-call structure is deterministic and compact;
- substantial latency drift occurs while the batching structure is unchanged;
- the Phase A evidence does not support batch under-utilization as the primary
  avoidable suffix-prefill bottleneck.

This does not claim that a larger batch can never be useful. It means the
specific Phase A hypothesis — poor packing/utilization — is not supported and
must not be used as justification for changing the frozen runtime.

### Candidate B — smaller / dynamic context proof

**SELECTED for controlled A/B.**

The next experiment will compare the frozen 512-token API context against a
manual 256-token experimental context while preserving:

- Accelerated runtime flags;
- batch=8 / ubatch=8;
- n_seq_max=1;
- C2-B;
- same model;
- same prompts;
- same output budget;
- same telemetry and termination semantics.

The 256-token option is an experimental proof target, not a new product default.

## Phase B gate

Build 48 should expose:

- **512 Baseline** — default;
- **256 Experimental** — manually selected before API startup.

The active context must be visible in diagnostics.

No admission-driven automatic context selection should be implemented until the
256-vs-512 true-device A/B demonstrates a repeatable benefit.
