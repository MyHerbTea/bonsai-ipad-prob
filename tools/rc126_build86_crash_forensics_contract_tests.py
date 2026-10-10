#!/usr/bin/env python3
"""Contract tests for Build86 crash forensics and portable privacy boundaries."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
view=(root/"BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
engine=(root/"BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
server=(root/"BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
flow=(root/".github/workflows/build-ios.yml").read_text(encoding="utf-8")
patch=(root/"tools/rc126_build86_patch_prism_crash_forensics.py").read_text(encoding="utf-8")
assert 'CURRENT_PROJECT_VERSION: "105"' in (root/"project.yml").read_text()
assert 'RC126APIStartupLifecycle.begin(build: "105")' in view
assert '"build_id": "rc1.26-build105-startup-recovery"' in server
assert "build86_crash_forensics_v2" in server
assert 'trace_format=2' in engine and 'trace_format=2' in view
assert "bonsai_build86_previous_native_trace.txt" in engine
assert "bonsai_build86_previous_native_trace.txt" in view
assert "复制完整原生崩溃追踪（当前及上次）" in view
assert "trace_total_lines=" in view and "trace_display_omitted_lines=" in view
assert "trace_last_native_event=" in view and "trace_last_fused_probe=" in view
assert "os_termination_cause=unknown_without_iPadOS_ips" in view
for marker in ("BUILD86_FUSED_PROBE_BEGIN","BUILD86_CONTEXT_SPLIT_BEGIN","BUILD86_SPLIT_ENTER",
               "BUILD86_PASS5_HEARTBEAT",
               "BUILD86_INVALID_ASSIGNMENT_PASS4","BUILD86_SPLIT_DONE"):
    assert marker in patch, marker
# Pass markers are deliberately emitted through an indexed generator in
# the Prism patcher, so test the generator and every unique upstream pass.
assert "BUILD86_SPLIT_PASS{num}_BEGIN" in patch
for expected in ("pass 1: assign backends", "pass 2: expand current",
                 "pass 3: upgrade nodes", "pass 4: assign backends",
                 "pass 5: split graph"):
    assert expected in patch, expected
assert "../../src/bonsai-build84-trace.h" in patch
assert "tools/rc126_build86_patch_prism_crash_forensics.py" in flow
assert "tools/rc126_build86_crash_forensics_contract_tests.py" in flow
assert "BonsaiLab-v1-RC1.26-build105-startup-recovery-unsigned.ipa" in flow
print("RC1.26 Build86 crash forensics v2 contracts: PASS")
