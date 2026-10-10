from pathlib import Path
root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab/LocalOpenAIServer.swift").read_text()
view = (root / "BonsaiLab/ProductionView.swift").read_text()
workflow = (root / ".github/workflows/build-ios.yml").read_text()
project = (root / "project.yml").read_text()
assert 'CURRENT_PROJECT_VERSION: "90"' in project or 'CURRENT_PROJECT_VERSION: "104"' in project
assert ('"rc1.26-build90-certification-p1"' in server or '"rc1.26-build104-integrated-32k-performance"' in server)
assert 'request.path == "/debug/request-trace"' in server
assert server.index('guard authorized(request) else') < server.index('request.path == "/debug/request-trace"')
assert 'payload.certificationTrace = certificationTrace' in server
assert 'BonsaiRequestTrace.from(headers: request.headers)' in server
assert 'recordCertificationTrace(' in server
assert 'certificationTraceLimit = 64' in server
assert 'payload.certificationTrace?.requestID' in view
assert 'RC126APIStartupLifecycle.begin(build: "103"' in view
assert 'BonsaiCertificationBuildIdentity.sourceGitSHA' in server
assert 'Embed exact product build identity' in workflow
assert 'github_run_id' not in server or 'workflow_run_id' in server
# Preserve the verified native inference implementation; P1 must not mutate it.
engine = (root / "BonsaiLab/BonsaiEngine.swift").read_text()
native_patch = (root / "tools/rc126_build89_patch_prism_compact_scheduler.py").read_text()
assert 'guard contextLength >= 32_768 else' in engine
assert 'BUILD89_META_USED' in native_patch
assert 'BONSAI_BUILD84_TRACE_PATH' in native_patch
assert '"capacity": certificationTraceLimit' in server
assert '"contains_prompts": false' in server
assert '"contains_secrets": false' in server
assert '"workflow_run_id": BonsaiCertificationBuildIdentity.workflowRunID' in server
print("Build90 P1 request correlation + Build89 inference isolation source contract PASS")
