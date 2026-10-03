# RC1.16 — Persistent Vision Session

Experimental branch derived from the green RC1.15 integration candidate.

## Hypothesis
Repeated questions against the same model, image/cache key, quality and runtime can retain the native llama_context and reuse KV state.

## Warm-path target
- image embedding cache: HIT
- resident full model: HIT
- resident context: HIT
- KV reuse: HIT
- context create time: ~0

## Invalidation
Changing the model lifecycle, image/cache key, context/runtime parameters, or exhausting context capacity invalidates the resident context.

RC1.15 remains untouched until GitHub Actions and real-device repeated-question testing pass.
