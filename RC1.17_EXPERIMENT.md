# RC1.17 — True Streaming

Derived from RC1.16.

Goals:
- preserve image/model/context/KV reuse
- fix first cold request context adoption so the second compatible request can reuse KV
- expose native incremental generation callbacks
- update the app answer while generation is in progress
- implement true HTTP/1.1 chunked SSE for OpenAI stream=true

Non-goal: adaptive resource policy remains a later RC.

Real-device acceptance requires multiple SSE data frames before generation completion and visible incremental UI output.
