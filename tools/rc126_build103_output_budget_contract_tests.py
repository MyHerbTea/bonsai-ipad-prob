#!/usr/bin/env python3
"""Build103 output-budget regression: static guard only; device run remains mandatory."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (root / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
engine = (root / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
project = (root / "project.yml").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

def expect(condition, reason):
    if not condition:
        raise AssertionError(reason)

expect('CURRENT_PROJECT_VERSION: "103"' in project, "new build identity")
expect('RC126APIStartupLifecycle.begin(build: "103")' in view, "startup identity")
expect('"build_id": "rc1.26-build103-integrated-output-stage"' in server, "server identity")
expect('?? maxOutputLimit' in server, "omitted output length must default to UI-configured ceiling")
expect('?? 256' not in server, "obsolete API parser 256-token default remains")
expect('min(maxOutputLimit, max(1, requested))' in server, "configured ceiling validation")
expect('(root["max_completion_tokens"] as? NSNumber)' in server, "max_completion_tokens support")
expect('(root["max_tokens"] as? NSNumber)' in server, "max_tokens support")
expect('(root["max_output_tokens"] as? NSNumber)' in server, "max_output_tokens support")
expect('gen.maxTokens = payload.maxTokens' in view, "validated budget must reach engine")
expect('min(\n                        payload.maxTokens,\n                        256' not in view, "hidden handler 256 cap")
expect('discovery_max_output_tokens=\\(apiMaxOutputTokens)' in view, "diagnostic must match UI value")
expect('Server Max Output Tokens: \\(apiMaxOutputTokens)' in view, "copied API config must reflect UI")
expect('Max Output Tokens: \\(apiMaxOutputTokens)' in view, "copied Chatbox config must reflect UI")
expect('Recommended Client Max Output: 128' not in view, "stale 128-token recommendation")
expect('clampOutputToContext: true' in view, "text context clipping must be enabled for API")
expect('let availableOutput = appliedRuntime.context - tokens.count - 1' in engine,
       "actual tokenizer-based text budget required")
expect('gen.maxTokens = min(gen.maxTokens, availableOutput)' in engine,
       "clip only to remaining context, not artificial constant")
expect('Int32(requireFullOutputBudget ? gen.maxTokens : 1)' in engine,
       "vision prefill must reserve only one token when requesting context clamp")
expect('requireFullOutputBudget:\n                                            false' in view,
       "vision API must opt into context clipping")
expect('maxOutputTokens: apiMaxOutputTokens' in view, "UI configured limit must be propagated")
expect('lab-v1-rc1-26-build103-integrated-output-stage' in workflow,
       "CI must run on integrated-stage branch")
expect('build103-integrated-output-stage-unsigned.ipa' in workflow,
       "Build103 IPA artifact must be published")
print("PASS Build103 parser -> handler -> text/vision engine -> metadata/API UI/output budget contracts")
print("DEVICE REQUIRED: >256 actual completions, stream/nonstream, context/vision, idle/crash memory")
