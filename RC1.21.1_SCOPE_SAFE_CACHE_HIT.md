# RC1.21.1 — Scope-Safe Cache Hit

## Real-device finding

RC1.21.0 second request to the same image returned immediately (~0.41 s) with a permission error opening the selected Q8 mmproj.

The two-phase runtime itself had not been re-entered. The failure happened while computing the content-addressed cache key.

## Root cause

prepareVisionEmbeddingCache previously did:

1. validate config;
2. makeVisionCacheURL(...);
3. inside that helper, read image bytes and mmproj file attributes;
4. only after cache lookup, call startAccessingSecurityScopedResource().

The first request could still inherit temporary document-picker access. After that scope ended, a second request attempted to stat the mmproj before re-opening its security scope.

## Fix

RC1.21.1 acquires security scopes for model, mmproj and image before cache-key computation and keeps them balanced with defer.

The cache-hit path still does not initialize mtmd or open the projector runtime. It only needs file access long enough to recompute the stable key:
SHA256(image bytes + model identity + mmproj identity + mmproj size + image token tier).

## Acceptance

Run the same image twice.

Expected second request:
- TWOPHASE_A00_SCOPE_READY
- TWOPHASE_A00_CACHE_HIT
- no TWOPHASE_A02_MMPROJ_BEGIN
- no 27B reload
- direct cached-embedding prefill and generation
- materially lower wall time than the first request.
