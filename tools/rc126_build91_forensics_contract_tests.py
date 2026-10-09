#!/usr/bin/env python3
"""Static observer-only Build91 contract; no device inference."""
from pathlib import Path
s = (Path(__file__).resolve().parents[1] / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
assert 'request.path == "/debug/execution"' in s
auth = s.index('guard authorized(request) else')
diag = s.index('request.path == "/debug/execution"')
assert auth < diag
for marker in [
    'private let forensicsLock = NSLock()',
    'private func forensicsSnapshot()',
    '"native_prefill_progress_available": false',
    '"cancellation_propagation_verified": false',
    'phase: "handler_running_stream"',
    'phase: "handler_running_nonstream"',
    'phase: "handler_error_stream", terminal: true',
    'phase: "handler_error_nonstream", terminal: true',
    'phase: "completed", terminal: true',
    'phase: "received", terminal: true',
]:
    assert marker in s, marker
segment = s[s.index('private func forensicsSnapshot()'):s.index('private func forensicsSnapshot()')+1300]
for forbidden in ['api_key', 'Authorization', 'systemPrompt', 'messages', 'raw_prompt']:
    assert forbidden not in segment, forbidden
print("Build91 P0 static forensics contracts: PASS")
