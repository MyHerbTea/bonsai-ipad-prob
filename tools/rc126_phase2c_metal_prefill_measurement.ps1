param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [string]$OutDir = "",
    [string]$ExpectedBuildId = "rc1.26-build69-metal-prefill-measurement"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "API key required. Pass -ApiKey or set BONSAI_API_KEY. Never commit the key."
}

$root = $BaseUrl.TrimEnd("/")
if ($root.EndsWith("/v1")) {
    $root = $root.Substring(0, $root.Length - 3)
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Get-Location) "re_output/rc126-phase2c0-capability-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$headers = @{ Authorization = "Bearer $ApiKey" }

function Get-BonsaiJson([string]$Path) {
    Invoke-RestMethod -Method Get -Uri ($root + $Path) -Headers $headers
}

$build = Get-BonsaiJson "/debug/build"
$prefill = Get-BonsaiJson "/debug/prefill"
$runtime = Get-BonsaiJson "/debug/runtime"
$health = Get-BonsaiJson "/health"

$build | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $OutDir "build.json")
$prefill | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $OutDir "prefill-capability.json")
$runtime | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $OutDir "runtime.json")
$health | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $OutDir "health.json")

if ($build.build_id -ne $ExpectedBuildId) { throw "Unexpected build_id: $($build.build_id)" }
if ($prefill.phase -ne "RC1.26_PHASE2C0_CAPABILITY_PROVENANCE_AUDIT") { throw "Unexpected phase: $($prefill.phase)" }
if ($prefill.metal_tensor_prefill_effective -ne $false) { throw "Safety violation: effective must remain false in 2C-0." }
if ($prefill.metal_tensor_prefill_policy -ne "capability_only_backend_latched") { throw "Unexpected policy." }
if ($prefill.backend_latch.runtime_toggle_safe -ne $false) { throw "Safety violation: runtime toggle cannot be reported safe." }
if ($prefill.provenance.prism_source_commit -ne "adfffbe41b2cabcd51fff326ab045662265062bb") { throw "Prism provenance mismatch." }
if ($prefill.provenance.xcframework_sha256 -ne "d23bb0325cca43054c1a76a233c79950a1ce26d98a359466c8d81fafd3b1d9ad") { throw "XCFramework provenance mismatch." }

$available =
    ($prefill.capability.metal_device_present -eq $true) -and
    ($prefill.capability.metal4_family_supported -eq $true) -and
    ($prefill.capability.tensor_library_compiled -eq $true) -and
    ($prefill.capability.tensor_pipeline_compiled -eq $true) -and
    ($prefill.capability.framework_metal_registry_present -eq $true) -and
    ([int]$prefill.capability.framework_embed_library -eq 1)

$decision = if ($available) { "PASS_CAPABILITY_AVAILABLE" } else { "PASS_CAPABILITY_UNAVAILABLE" }
$summary = [ordered]@{
    captured_at = (Get-Date).ToString("o")
    base_url = $BaseUrl
    build_id = $build.build_id
    phase = $prefill.phase
    decision = $decision
    candidate_probe_eligible = [bool]$prefill.candidate_probe_eligible
    metal_device = $prefill.metal_device
    metal4_family_supported = [bool]$prefill.capability.metal4_family_supported
    tensor_library_compiled = [bool]$prefill.capability.tensor_library_compiled
    tensor_pipeline_compiled = [bool]$prefill.capability.tensor_pipeline_compiled
    framework_metal_registry_present = [bool]$prefill.capability.framework_metal_registry_present
    framework_embed_library = [int]$prefill.capability.framework_embed_library
    failure_stage = [int]$prefill.capability.failure_stage
    error_code = [int64]$prefill.capability.error_code
    probe_duration_ns = [int64]$prefill.capability.probe_duration_ns
    ggml_metal_tensor_disable = $prefill.ggml_metal_tensor_disable
    runtime_toggle_safe = [bool]$prefill.backend_latch.runtime_toggle_safe
    metal_tensor_prefill_effective = [bool]$prefill.metal_tensor_prefill_effective
}
$summary | ConvertTo-Json -Depth 20 | Tee-Object -FilePath (Join-Path $OutDir "summary.json")
Write-Host ""
Write-Host "Phase 2C-0 capability audit: $decision"
Write-Host "Evidence: $OutDir"
