# Bonsai Build105 — safe 32K startup recovery

## Incident
On Build104 the user's 32768-context API crashes the process. The native trace contains only `build=89 trace_format=2 context=32768 started=...`. No native phase entries follow. `build=89` is a trace compatibility identifier, not the App build. A second recurrent KV sequence (n_seq_max=2) was enabled by default in Build104 without successful iPad certification. This is a strong suspect, but the supplied trace alone cannot prove the precise native fault.

## Fail-closed recovery
- Build105 **unconditionally** uses n_seq_max=1 (Build103 single-sequence baseline). Dual-sequence KV and KV reuse are quarantined for all contexts, including when persisted Build104 preferences remain true.
- One-time first-launch migration resets B24/B16 auto preferences and disabled experimental KV key, preserving pending candidate failure with sticky SAFE4. If no pending and no safety fallback, schedule baseline8.
- B24 is manually opt-in after separate healthy 32K start, only if local baseline/B16/B24 qualification exists; it does not auto-enable.
- Preserve OpenAI API full output ceiling, image and SSE/multi-turn contracts. Do not disturb selected model, API key or context.
- Native trace adds app_build=105, batch, seq_max and quarantine status for next failure diagnosis.

## Integrated acceptance
macOS CI builds pinned Prism, compiles Swift executable policy tests and entire iOS app, emits unsigned IPA plus Windows GUI ZIP. Device test checks actual App build=105, 32K health, max output beyond 256, streaming, multi-turn, long input, 1–3 auto-generated PNG image, post-vision text, and effective seq_max=1 / KV quarantine. **No KV acceleration claim.** Model weight files are not bundled.

Install Build105 over prior app (do not uninstall), start API, extract one-click ZIP and double-click RUN_BUILD105_FULL_STAGE.cmd; paste API Key in visible Windows GUI. Upload RESULTS/Build105-FULL-*.zip. If process still crashes during initialization, return to previously tested Build103 and preserve new trace; never force repeated unsafe startups.
