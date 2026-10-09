# BonsaiLab 32K Certification — P0 Windows runner

This is the first **non-invasive** certification iteration. It runs against the **unchanged Build 89 IPA** using OpenAI-compatible LAN HTTP. It does not recompile Prism or attempt a 64K context.

## Start

Requirements: Python 3.10+ on Windows (stdlib only), LAN/Tailscale path to iPad, Bonsai API already started in the iPad app.

Copy `config.example.json` to `config.local.json` and enter your **private** Base URL / API Key. Alternatively set `BONSAI_API_KEY` in your session. Do **not** commit or publicly share `config.local.json`.

Double-click `RUN_SMOKE.cmd`, or use:

```powershell
py -3 device_tests/certify.py --config device_tests/config.local.json --suite smoke
```

Read-only reconnaissance (no model generation):

```powershell
py -3 device_tests/certify.py --config device_tests/config.local.json --suite readonly
```

## Checks

1. GET /health, require status=ok + context_window=32768.
2. GET /v1/models, require model ID, effective context, output cap=256.
3. GET /debug/build (Bearer), require Build 89 id.
4. GET /debug/telemetry and /debug/prefill (Bearer).
5. Smoke only: 32-token non-stream text request; 64-token SSE request; post-inference health, metrics, telemetry.
6. Creates self-contained `results/<run-id>.zip` with JSON summaries and synthetic response bodies.

Client adds `X-Bonsai-Run-ID`, `X-Bonsai-Request-ID`, `X-Bonsai-Test-Case`, but **Build89 does not yet persist or echo them**. Server-side correlation remains P1 work, explicitly marked unverified in the output.

**Never infer** a product git SHA from `/debug/build.baseline_commit`; it points to an older frozen baseline, not the installed product SHA. Build89 `/health.status` is `ok`, not `ready`.

This runner intentionally does **not** run large 32K prompts, induce memory exhaustion, start/stop the iPad app, or cancel inference. It is the P0 foundation, not final 32K certification.

## Confidentiality

No Authorization header or API key is written into results or evidence ZIP. Inputs are fixed synthetic text. The `results/` directory is excluded from source control; inspect raw synthetic responses before sharing anyway.

## Next P1

Add app-side immutable product identity manifest, validate the CI SHA against installed app, accept and persist request IDs through `LocalOpenAIServer` and `RC1232PerformanceDiagnostics`. Do not modify Build89's verified 32K memory path.
