# RC1.26 Phase 2H0 — Practical 2048 Device Evidence

Captured: 2026-10-07 10:16–10:18 +08:00

## Verdict

**PASS FUNCTIONAL / CONTEXT-COST BOTTLENECK CONFIRMED**

Parent:
- Build 75 certified binary commit: `c09b2e09706dd0c0391b7a15727da57e0f17d425`
- runtime shape: 32×32
- context: 2048
- Metal Tensor disabled
- Full / Accelerated profile

All 9 practical API cases passed:
1. short answer;
2. sustained 128-token answer;
3. medium context;
4. ~1K context;
5. ~1.5K context;
6. near-limit context;
7. multi-turn history;
8. streaming SSE;
9. explicit overflow rejection.

Final health remained `ok`.

## Context scaling

| Case | Prompt tokens | Prefill | TTFT | Result |
|---|---:|---:|---:|---|
| short | 31 | 15.962 ms | 713.753 ms | PASS |
| sustained | 83 | 1,248.949 ms | 1,845.342 ms | PASS |
| medium | 628 | 11,744.296 ms | 12,340.294 ms | PASS |
| ~1K | 1089 | 21,238.032 ms | 21,309.242 ms | PASS |
| ~1.5K | 1630 | 38,721.008 ms | 39,526.345 ms | PASS |
| near-limit | 1898 | 46,222.043 ms | 46,955.989 ms | PASS |

Observed prompt-prefill throughput:
- 628 tokens: ~53.47 tok/s
- 1089 tokens: ~51.28 tok/s
- 1630 tokens: ~42.10 tok/s
- 1898 tokens: ~41.06 tok/s

The model returned each requested codeword exactly, including near-limit input.

## Sustained decode

83-token prompt + 128-token completion:
- prefill: 1,248.949 ms
- decode-to-first: 596.393 ms
- TTFT: 1,845.342 ms
- sustained decode: 13.393 tok/s

This confirms interactive decode speed is usable when prompt history is short.

## Multi-turn / streaming / overflow

Multi-turn history:
- codeword `ORCHID-75-PRACTICAL` retained correctly.

Streaming:
- SSE data chunks observed;
- `[DONE]` observed.

Overflow:
- HTTP 400;
- code `context_length_exceeded`;
- server reported 3060 prompt tokens vs Context 2048.

## Resource state

End-of-test:
- health: `ok`
- thermal: `nominal`
- available memory: 4,863,191,400 bytes
- resident: 6,431,637,504 bytes
- Metal allocated: 6,272,827,392 bytes
- Metal recommended working set: 8,589,950,976 bytes
- Metal headroom: 2,317,123,584 bytes

No crash or runaway memory growth occurred.

## Product interpretation

Build 75 is practically usable for:
- short/medium chat;
- short code snippets;
- short multimodal prompts;
- lightweight multi-turn API use.

However 2048 is not a satisfactory long-context product target.

More importantly, long-history latency is already a blocker before capacity itself:
- ~1K history costs ~21 s TTFT;
- ~1.5K history costs ~40 s TTFT;
- near 2K costs ~47 s TTFT.

Simply exposing 4096/8192 without changing history reuse would increase capacity but would not produce a good long-context user experience.

## Next-stage recommendation

Do not spend Build 76 on another decode knob.

Priority:
1. retain Build 75 as the stable checkpoint;
2. open a Text Context / Prefix-Reuse lab;
3. prove repeated or growing conversation history can reuse the unchanged prefix/KV rather than clearing and re-prefilling the whole request;
4. once reuse is safe, expand capacity to 3072/4096;
5. only then decide whether 6144/8192 is worthwhile.

Evidence ZIP:
- `rc126-phase2h0-practical-2048-v2-20261007-101622.zip`
- SHA-256: `b315cbb8748dbd36b66aa883f69299f9f4e8faab6b0a5b3ae8ce45b1dad33bde`
