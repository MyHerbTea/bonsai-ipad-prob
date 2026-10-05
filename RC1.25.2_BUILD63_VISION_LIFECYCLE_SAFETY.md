# RC1.25.2 Build 63 — Vision Lifecycle Safety

## Trigger

Build 62 fixed the Context/Profile switching crash and passed repeated context
switching. During the final 2048 automated certification, the following sequence
was observed on-device:

- text/API compatibility tests: PASS
- 1-image vision: PASS
- 2-image vision: PASS
- 3-image vision: PASS
- next visual follow-up: TCP connection reset and the iPad app terminated
- after relaunch, the API worked again

This isolates the remaining failure to repeated vision lifecycle pressure rather
than 2048 context admission or general API transport.

## Root cause analysis

The OpenAI vision path performs MLX vision encoding before native cached-vision
prefill. Native prefill clears llama working memory on a cache miss, but that
clear occurs *after* MLX encoding has already started.

A previous text/vision request can therefore leave request-local KV/live context
state present while the next MLX vision forward allocates its own Metal/MLX
working set. The final certification reproduced the failure only after several
successful vision requests, with the next visual follow-up terminating the
process during this coexistence boundary.

The server is stateless between OpenAI requests; request-local KV is not needed
for correctness after a response completes. Optional vision prefix reuse uses an
independent native snapshot and does not require live working KV to remain.

## Build 63 fix

Build 63 keeps the resident 27B mmap model and llama context object but bounds
request-local memory more aggressively:

1. before every MLX vision encode, clear current llama working memory;
2. preserve optional prefix-reuse metadata/snapshot;
3. run MLX encode and cached-vision generation;
4. after a successful vision answer, clear request-local llama working memory;
5. clear MLX allocator cache after successful completion;
6. persist fine-grained request stages.

No full model reload or context recreation is introduced by this fix.

## Crash-stage diagnostics

The product now persists:

- `pre_encode_context_drain`
- `mlx_encode_begin`
- `mlx_encode_done`
- `native_prefill_begin`
- `success_cleanup_begin`
- `complete`

`/health` exposes:

- last engine stage
- last MLX vision stage
- current vision request stage
- context switch state
- last API image count/layout

A resumable external certification harness can therefore capture the last stage
after an app relaunch instead of losing the failed run.

## Acceptance gate

Build 63 must repeat the exact stress sequence that failed Build 62:

1. 2048 + ACCELERATED;
2. text/API compatibility smoke;
3. 1 image;
4. 2 images;
5. 3 images;
6. immediate prior-turn visual follow-up;
7. post-vision text survival;
8. repeat the 3-image -> visual-follow-up boundary at least twice.

Only after this passes should SDK checks and final freeze evidence be accepted.
