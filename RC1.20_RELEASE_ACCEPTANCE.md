# RC1.20 Product RC — Release Acceptance

RC1.20 is a release candidate, not a frozen release, until real-device acceptance passes.

## One-tap device certification
Use the same PTQ1_0 main model, Q8 mmproj and a representative complex image, then run **一键设备认证**.

PASS requires:
- Fast / 512 preset PASS
- Standard / 768 preset PASS
- Detailed / 1024 preset PASS
- Warm-session test PASS
- second warm request reports image cache HIT
- resident model HIT
- resident context HIT
- KV reuse HIT
- full model load and context-create times near zero on that warm request

The certification deliberately bypasses the resource governor so each fixed quality tier is tested honestly.

## Product checks
- Local answer text appears incrementally while generation is running.
- Resource governor decisions are visible in diagnostics.
- Starting the LAN API shows Base URL, model and API key.
- **复制 API 配置** puts those three values on the clipboard.
- stream=false returns a normal chat completion JSON.
- stream=true returns multiple SSE chunks before generation finishes.
- stream_options.include_usage emits a final usage chunk.
- GET /v1/models and GET /v1/models/bonsai-2-27b-local work.
- Unknown model names return model_not_found.
- App backgrounding stops the API and releases resident state.

## Freeze rule
Only after the real iPad M5 checks above pass should RC1.20 be promoted to a frozen product baseline.
