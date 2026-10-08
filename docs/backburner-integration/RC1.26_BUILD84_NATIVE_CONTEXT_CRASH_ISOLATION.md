# RC1.26 Build 84 — Native Context Crash Isolation

Build 83 failed the real-device 32K test on iPad Pro M5 (iPadOS 27.0.1): model load completed, but context creation did not. GitHub Actions #472 compiled Build 83 successfully but did not verify on-device initialization.

Build 84 retains exactly the Build 83 KV sharding strategy, Build 82 GPU99 32K policy, and frozen 16K settings. The only native change is crash-persistent diagnostic breadcrumbs in llama-context.cpp and llama-kv-cache.cpp. It adds a per-attempt App Support trace file, enabled only for >=32768 context, and fsyncs native stages so a subsequent launch can display them.

## One-shot test

1. Install Build 84 via the existing signing workflow; select the 27B GGUF.
2. Optionally verify 16384 safe profile first.
3. Select 32768 and start the local API **once**. Do not repeat a crash loop.
4. If the app terminates, reopen it and copy the full snapshot including [BUILD 84 NATIVE CONTEXT CRASH TRACE].
5. To restore service manually select 16384; do not assume 32K success.

## Native trace interpretation

* CTX_MEMORY_BEGIN only: failure during memory/KV construction.
* KV_SHARD_ROUTE shows actual per-layer routing, not a compile-time claim.
* KV_ALLOC_BEGIN without DONE: backend allocation failure boundary.
* KV_CLEAR_BEGIN without DONE: buffer zeroing failure boundary.
* CTX_MEMORY_DONE without CTX_SCHED_DONE: backend/scheduler failure boundary.
* trace_present=false: trace setup or pre-native failure; obtain iPadOS .ips log.

This is a **diagnostic** release, not a 32K fix. CI PASS does not certify real-device performance, vision or reboot stability. The model files and user prompts/images/API keys are not embedded in trace records.
