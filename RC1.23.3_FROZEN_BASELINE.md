# RC1.23.3 FROZEN ACCELERATED PERFORMANCE BASELINE

Status: **FROZEN**
Frozen build: **45**
Frozen source commit: `0e9b14746a85b2035f0d06b88197d338b8b8bc4a`

## Release evidence

- GitHub Actions run: **#29**
- Run ID: `37195133828`
- CI conclusion: **SUCCESS**
- Artifact: `BonsaiLab-iPad-v1-RC1.23.3-Build45-Accelerated-Baseline-Candidate`
- Artifact ID: `11301100823`
- Artifact size: **7,443,849 bytes**

## Frozen product decision

RC1.23.3 freezes the API runtime profile decision established by true-device
build-44 A/B testing and the accelerated 12-HIT soak:

- **Full / Accelerated** is the default performance profile.
- **Safe** remains the compatibility fallback.
- The rejected Flash-only profile is not exposed.
- Stale persisted Flash-only selection migrates to Accelerated.

## True-device performance evidence

Safe baseline:
- six warm HIT average: about **22.95 s**;
- sustained decode throughput: roughly **6.1–6.6 tok/s**.

Accelerated short A/B:
- six warm HIT average: about **18.73 s**;
- about **18% faster** than Safe;
- sustained suffix prefill around **2.0 s**;
- sustained decode throughput around **7.5 tok/s**.

Accelerated stability soak:
- one seed + twelve warm HIT requests;
- **13/13 HTTP 200**;
- twelve warm HIT average: about **19.34 s**;
- HIT2–12 average: about **19.92 s**;
- final six warm HIT average: about **20.24 s**;
- final-six throughput average: about **7.27 tok/s**;
- final request: **7.131 tok/s**, **17.949 s decode**, **2.153 s suffix prefill**;
- Metal allocation remained about **6110 MiB**;
- available memory remained about **4.46 GiB**;
- no crash or monotonic resource accumulation was observed.

## Frozen C2-B invariants

The following remain frozen and must not regress:

1. `n_seq_max=1`.
2. Same-sequence ON_DEVICE C2-B state checkpoint save/restore.
3. Warm reuse remains `HIT + retained=true`.
4. Warm HIT prefix/image prefill remains zero.
5. Reuse identity and invalidation semantics remain unchanged.
6. BVCACHE1 remains unchanged.
7. Projection width remains 5120.
8. RC1.22.5 MLX hard graph-cut behavior remains unchanged.
9. RC1.23.1 OpenAI multimodal/error behavior remains unchanged.
10. Privacy diagnostics continue excluding API keys, raw image/base64, prompt text,
    and assistant output.

Rejected paths remain rejected:
- C1 partial KV trim.
- C2-A multi-sequence checkpointing.
- Flash-only runtime profile as a performance product option.

## Immutability rule

Build 45 is now the RC1.23.3 frozen executable baseline. Future optimization
work must start from this baseline and must not silently modify its frozen
behavior. Any change to generation/decode behavior belongs to the next stage
and requires separate evidence.

## Next stage

Proceed to **RC1.23.4 — Generation / Decode Efficiency**.

Primary question: why controlled multimodal requests commonly consume the full
128-token completion budget, and how much decode work can be reduced while
preserving OpenAI-compatible max-token semantics, EOG/stop behavior, answer
quality, text recovery, multimodal correctness, and the frozen C2-B baseline.
