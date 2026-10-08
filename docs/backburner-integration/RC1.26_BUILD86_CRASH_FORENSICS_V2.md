# RC1.26 Build86 — Crash Forensics v2 (32K)

## Confirmed by Build85 on iPad Pro M5

32K model load PASS, all 16 Metal KV fragments PASS, scheduler initialization PASS, graph result allocation PASS, memory init PASS. During fused op compatibility resolution, a 1-token graph with 4,831 nodes was successfully constructed. The process ended before returning from graph splitting. Root cause (assert, bad pointer, jetsam, backend support failure) is **not yet established**.

## Build86 changes

* Keep Build83 KV sharding and Build84/85 trace markers, frozen 16K policy, and all existing inference arithmetic unchanged.
* Add Build86 precise probe name and dispatch events in Prism llama-context.cpp.
* Instrument the five passes of `ggml_backend_sched_split_graph` in ggml/src/ggml-backend.cpp, with sampled node-progress and output counts.
* On subsequent 32K attempts, save a copy of the previous trace to Application Support before resetting the current trace.
* Extend snapshot with trace byte count, total lines, last fused probe, last native event, last backend split event, trace-completed status and missing-lines notice.
* Add **复制完整原生崩溃追踪（当前及上次）** UI action that copies both complete trace files.
* Native tracing is enabled only when 32K+ via the existing environment latch; this is a forensics release and does not certify 32K.
* No prompt/image/token, API key or model contents are written. OS jetsam/abort cause still needs an iPadOS .ips report.

## One-shot real-device test

1. Install Build86 unsigned IPA from a successful GitHub Actions run.
2. Launch; select 27B GGUF. If useful, verify the historically accepted 16K tier first.
3. Select 32768 and start API once. If app exits, reopen immediately.
4. Use **刷新并复制完整诊断** to capture summary, followed by **复制完整原生崩溃追踪（当前及上次）** if trace_display_omitted_lines is nonzero.
5. Report final `BUILD86_*` lines. Do not loop repeated 32K starts. Manually select 16384 to recover a working API.

## Interpretation

* FUSED_PROBE_BEGIN identifies specific fused feature under test, likely GDN AR/CH (to be verified).
* CONTEXT_SPLIT_BEGIN and SPLIT_ENTER place the error inside graph scheduler backend assignment.
* SPLIT_PASS1-5_BEGIN + PASS5_HEARTBEAT identify the phase and approximate node interval.
* INVALID_ASSIGNMENT_PASS4 preceding termination supports an unsupported node/backend assertion.
* SPLIT_DONE without FUSED_PROBE_GRAPH_DONE indicates trouble in fused probe post-processing.

Build86 CI PASS is only a compile/contract gate, not 32K real-device PASS.
