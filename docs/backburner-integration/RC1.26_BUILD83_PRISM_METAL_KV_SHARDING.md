# RC1.26 Build 83 — Prism Metal KV Sharding

Build 82 proved that the 32K failure is inside llama_init_from_model() after model mmap/load succeeds. Effective settings were Q4, 99 GPU layers, batch/ubatch 4/4, Flash Attention ON, KQV/Op offload ON, with about 4974 MiB available before context creation.

Prism's Qwen3.5 hybrid memory keeps recurrent state at rs_size=max(1,n_seq_max), so recurrent state does not scale with 32K. sched_reserve() also uses min(n_ctx,n_ubatch), which is 4 here.

The remaining structural issue is attention KV allocation: llama_kv_cache groups all tensors sharing one backend buffer type into one ggml context and one backend allocation. The Metal owned-buffer path creates one MTLBuffer for that context, unlike the mmap mapping path which has maxBufferLength-aware splitting.

Build 83 changes only this allocation grouping. For QWEN35/QWEN35MOE with offloaded KV, Metal device, and kv_size >= 32768, the context key becomes (buffer type, layer id). Each full-attention layer receives its own KV backend allocation. 16K, CPU KV, other models, tensor shapes, Q4 format and attention math remain unchanged.

Prism base commit: adfffbe41b2cabcd51fff326ab045662265062bb.
