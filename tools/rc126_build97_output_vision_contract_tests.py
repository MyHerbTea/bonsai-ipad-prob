#!/usr/bin/env python3
"""Build97 output budget and home Vision selection source contracts.

These tests do not substitute for actual iPad long-output and vision regression.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab/ProductionView.swift").read_text()
server = (root / "BonsaiLab/LocalOpenAIServer.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github/workflows/build-ios.yml").read_text()

assert 'CURRENT_PROJECT_VERSION: "97"' in project
assert 'RC126APIStartupLifecycle.begin(build: "97")' in view
assert '"build_id": "rc1.26-build97-output-config-vision-home"' in server
assert 'BonsaiBuild97APIMaxOutputTokens' in view
assert '[256, 512, 1024, 2048, 4096, 8192, 16384, 32768]' in view
assert 'maxOutputTokens: apiMaxOutputTokens' in view
assert 'maxOutputTokens: 256' not in view
assert 'max(1, contextWindow - 1)' in server
assert 'min(maxOutputLimit, max(1, requested))' in server
assert 'contextWindow: advertisedContextWindow' in server
assert 'maxOutputLimit: advertisedMaxOutputTokens' in server
assert 'let maxTokens = min(\n            2048,' not in server
assert '?? 256' in server, 'Keep modest default when clients omit max_tokens'
assert view.index('Section("模型")') < view.index('Section("MLX Vision Sidecar")') < view.index('Section("图片")')
assert view.index('Section("MLX Vision Sidecar")') < view.index('DisclosureGroup(\n                        "高级与诊断"')
assert view.count('Text("MLX Vision Sidecar Probe")') == 1
assert 'runMLXVisionProbe()' in view and 'runLiveVisionInjection()' in view
assert 'Build97-Output-Config-Vision-Home' in workflow
assert 'build97-output-config-vision-home-unsigned.ipa' in workflow
print("PASS Build97 output budget, homepage MLX Vision placement and release identity contracts")
