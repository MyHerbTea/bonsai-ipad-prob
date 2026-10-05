# RC1.26 Phase 2C — Metal Prefill Measurement Gate

Phase 2C is measurement-only. It does not enable the Metal Tensor API.

Purpose: establish direct baseline measurements for prompt prefill milliseconds, prompt prefill tokens/second, decode-to-first-token milliseconds, total TTFT, decode throughput, memory, Metal allocation, and thermal state.

The existing M5 workaround GGML_METAL_TENSOR_DISABLE=1 remains active.

Debug endpoint: GET /debug/prefill

Passing Phase 2C authorizes only a later isolated correctness-first Metal Tensor A/B experiment. It does not promote Metal Tensor into ACCELERATED or default behavior.
