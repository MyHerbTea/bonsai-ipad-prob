# RC1.26 Build 76 — M5 Extreme Context Lab Plan

## Objective

Exploit the iPad Pro M5 aggressively while preserving a one-click fallback to Build 75 semantics.

## Phase order

### 76-A: Text KV correctness at 2048
Implement:
- resident text token ledger;
- exact longest-common-prefix;
- live KV tail trim with `llama_memory_seq_rm`;
- suffix-only `llama_decode`;
- generated token ledger;
- fallback full-clear/full-prefill.

Do not expand context yet.

Gate:
- deterministic answer equivalence;
- zero contamination;
- measurable prefill hit.

### 76-B: Reuse stress
Run:
- 10–20 growing-turn conversation;
- 600/1000/1500/1900-token history;
- short and 128-token outputs;
- streaming and non-streaming;
- failure/cancel/reset transitions.

Gate:
- TTFT follows suffix length;
- no KV corruption;
- no memory creep.

### 76-C: Capacity push
With reuse ON and OFF controls:
1. 3072
2. 4096
3. 6144
4. 8192

For every tier capture:
- context-create time;
- available memory;
- resident/footprint;
- Metal allocated/recommended/headroom;
- 128-token decode;
- 50%, 75%, 90% context prefill;
- cold first API start;
- text→Vision→text.

Stop a tier only on:
- app termination/jetsam;
- context creation failure;
- unacceptable memory headroom;
- correctness regression;
- major Vision/cold-start regression.

### 76-D: Max-M5 prefill sweep
Only after context/reuse correctness:
- 32×32 baseline
- optionally test asymmetric batch/uBatch shapes supported by Prism
- reconsider 64 only for long prefill if decode path can remain unaffected
- never promote a shape on prefill gain alone.

## Promotion target

A future stable release should ideally ship:
- 4096 as minimum normal context;
- 8192 if device evidence passes;
- Text KV reuse enabled by default;
- Build 75-compatible fallback;
- current ~13 tok/s interactive decode preserved.
