param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "Set BONSAI_API_KEY or pass -ApiKey."
}

$root = $BaseUrl.TrimEnd("/")
if ($root.EndsWith("/v1")) {
    $root = $root.Substring(0, $root.Length - 3)
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Get-Location) "re_output/rc126-build75-cold-start-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$headers = @{
    Authorization = "Bearer $ApiKey"
}

function Get-BonsaiJson([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers
}

function Save-Json($Value, [string]$Name) {
    $Value |
        ConvertTo-Json -Depth 30 |
        Set-Content -Encoding utf8 (Join-Path $OutDir $Name)
}

$build = Get-BonsaiJson "/debug/build"
$health = Get-BonsaiJson "/health"
$phase2f = Get-BonsaiJson "/debug/phase2f/launch"

Save-Json $build "build.json"
Save-Json $health "health.json"
Save-Json $phase2f "phase2f-launch.json"

if ($build.build_id -ne "rc1.26-build75-api-cold-start-guard") {
    throw "Unexpected build_id: $($build.build_id)"
}

$diag = $health.diagnostics
if ($null -eq $diag) {
    throw "Health response does not contain diagnostics."
}

$summary = [ordered]@{
    captured_at = (Get-Date).ToString("o")
    build_id = $build.build_id
    health_status = $health.status
    startup_stage = [string]$diag.api_startup_stage
    startup_previous_incomplete = [string]$diag.api_startup_previous_incomplete
    startup_attempt = [int]$diag.api_startup_attempt
    startup_last_error = [string]$diag.api_startup_last_error
    phase2f_launch_arm = [string]$phase2f.launch_arm
    phase2f_next_launch_arm = [string]$phase2f.next_launch_arm
    active_batch = [int]$phase2f.active_batch
    active_ubatch = [int]$phase2f.active_ubatch
    shape_evidence_valid = [bool]$phase2f.shape_evidence_valid
    process_launch_id = [string]$phase2f.process_launch_id
}
Save-Json $summary "summary.json"

if ($summary.startup_stage -ne "READY") {
    throw "API startup lifecycle is not READY: $($summary.startup_stage)"
}

if ($summary.active_batch -ne 32 -or $summary.active_ubatch -ne 32) {
    throw "Build 75 stabilization expected 32/32, got $($summary.active_batch)/$($summary.active_ubatch)."
}

$zipPath = "$OutDir.zip"
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath

Write-Host ""
Write-Host "Build 75 API cold-start probe: PASS"
Write-Host "Startup stage: $($summary.startup_stage)"
Write-Host "Previous incomplete: $($summary.startup_previous_incomplete)"
Write-Host "Startup attempt: $($summary.startup_attempt)"
Write-Host "Batch/UBatch: $($summary.active_batch)/$($summary.active_ubatch)"
Write-Host "Evidence: $zipPath"
