# RC1.23.5 Build 48 — Dynamic Context Controlled A/B

Status: **PHASE B EXPERIMENTAL CANDIDATE**

Parent evidence:
- RC1.23.5 Build 47 Phase A profiling
- Phase A result: batched-prefill under-utilization hypothesis rejected
- 512-context frozen behavior remains the baseline

## Purpose

Build 48 answers one narrow question:

> Does reducing API context from 512 to 256 materially improve TTFT and suffix
> prefill for controlled multimodal requests while preserving the frozen runtime,
> C2-B behavior, output budget, termination semantics, and answer quality?

Build 48 is not an automatic dynamic-context product implementation.

It exposes two explicit pre-start profiles:

- **512 Baseline** — default
- **256 Experimental** — manual A/B candidate

The context selector is locked while the API server is running.

## Frozen boundaries

Build 48 does not intentionally change:

- Accelerated runtime flags;
- Safe fallback behavior;
- batch=8;
- ubatch=8;
- n_seq_max=1;
- C2-B same-sequence checkpoint save/restore;
- Vision Prefix KV reuse identity/invalidation;
- model;
- sampler;
- max-token semantics;
- EOG/length termination provenance;
- Build 46 telemetry field meanings;
- Build 47 suffix-prefill profiling field meanings;
- PowerShell UTF-8 behavior.

## Diagnostic contract

The runtime snapshot must expose:

- `api_context=<actual active context>`
- `rc1235_api_context_requested=<requested context>`
- `rc1235_api_context_active=<active context>`
- `rc1235_api_context_profile=<requested profile>`

The frozen `api_context` field keeps its original meaning: the actual API
runtime context. It is no longer hard-coded to 512 because Build 48 explicitly
runs a 256-context experiment.

## Why 256 is safe for the controlled proof

For the Phase A controlled prompts:

### Concise English Vision

Observed:
- prefix positions: 24
- suffix tokens: 29
- output budget: 128

Required positions including one guard position:

```text
24 + 29 + 128 + 1 = 182
```

256 leaves approximately 74 positions of headroom.

### Chinese descriptive Vision

Observed:
- prefix positions: 24
- suffix tokens: 22
- output budget: 128

```text
24 + 22 + 128 + 1 = 175
```

256 leaves approximately 81 positions of headroom.

This calculation applies only to the controlled proof workload. It is not an
argument that all API requests should use a 256-token context.

## A/B methodology

Do not run all 512 samples first and all 256 samples second.

Phase A showed strong sustained-performance drift despite:
- fixed prompt;
- fixed suffix token count;
- fixed decode-call count;
- fixed batch packing;
- public thermal state remaining nominal.

Therefore Build 48 testing should use an alternating or otherwise balanced
order.

Recommended sequence:

```text
512-A
256-A
512-B
256-B
512-C
256-C
512-D
256-D
```

Each profile switch requires stopping and restarting the API runtime because the
context size is fixed when the llama context is created.

For each run:
- same app build;
- same model;
- same image;
- same prompt;
- same 128-token output budget;
- Accelerated runtime;
- Prefix KV reuse enabled;
- establish warm HIT before recording the scored request.

## Primary decision metrics

Compare medians first:

- `ttft_ms`
- `suffix_prefill_ms`
- `rc1235_suffix_ms_per_decode_call`
- `total_ms`

Guardrails:

- `rc1235_suffix_tokens`
- `rc1235_suffix_decode_calls`
- `rc1235_suffix_batch_utilization`
- decode TPS
- completion tokens
- termination reason
- finish reason
- Prefix KV HIT / retained
- available memory
- physical footprint
- Metal allocation
- answer completeness

## Acceptance rule

A 256-context candidate should only advance to an automatic context-selection
design if it shows a repeatable, meaningful improvement in TTFT/suffix prefill
under controlled A/B while all guardrails pass.

A single fastest request is not sufficient.

If 256 provides no meaningful repeatable gain, reject Dynamic Context and keep
the RC1.23.4 Build 46 frozen baseline as the production runtime behavior.

If 256 does show a worthwhile gain, the next implementation must still be a
separate admission-driven design. Build 48 itself remains an experiment.
