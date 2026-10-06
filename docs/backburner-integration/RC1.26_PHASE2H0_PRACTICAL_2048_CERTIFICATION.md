# RC1.26 Phase 2H0 — Practical 2048 Workload Certification

Status: RUNNER-ONLY / NO PRODUCT CHANGE

Parent checkpoint:
- Build 75 certified binary: c09b2e09706dd0c0391b7a15727da57e0f17d425
- context: 2048
- batch/uBatch: 32/32
- Full / Accelerated profile
- Metal Tensor disabled

Judgement before testing:
- Interactive decode speed is already usable.
- 2048 context is not a satisfactory long-context target.
- Text requests clear working KV before each request, so longer histories are re-prefilled.

Phase 2H0 certifies practical behavior at the existing 2048 context:
1. short single-turn answer;
2. 128-token sustained answer;
3. ~600-token input;
4. ~1000-token input;
5. ~1500-token input;
6. near-capacity input;
7. multi-turn history retention;
8. streaming SSE;
9. explicit context-overflow rejection.

If this passes, the next product build should be a Context Capacity Lab:
2048 -> 3072 -> 4096 first, then decide whether 6144/8192 is worthwhile.
