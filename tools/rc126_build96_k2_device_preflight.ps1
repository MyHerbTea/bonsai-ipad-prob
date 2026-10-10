# Build96 K2: read-only device preflight with optional guarded next-launch scheduling.
# Requires PowerShell 7; never records the API key or prompt/completion content.
param(
  [Parameter(Mandatory=$true)][string]$BaseUrl,
  [string]$ApiKey=$env:BONSAI_API_KEY,
  [ValidateSet("","BASELINE8","CANDIDATE16","SAFE4")][string]$ScheduleNext="",
  [string]$OutDir=""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Provide BONSAI_API_KEY or -ApiKey" }
$base = $BaseUrl.TrimEnd("/")
if ($base.EndsWith("/v1")) { $base = $base.Substring(0,$base.Length-3) }
if ($base -notmatch '^https?://[^/]+$') { throw "BaseUrl must be http(s)://HOST:PORT or http(s)://HOST:PORT/v1" }
if (-not $OutDir) { $OutDir = Join-Path (Get-Location) ("re_output/build96-preflight-" + (Get-Date -Format "yyyyMMdd-HHmmss")) }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$headers = @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }
function Read-Endpoint([string]$path) {
  Invoke-RestMethod -Uri "$base$path" -Headers $headers -Method Get -TimeoutSec 20
}
function Save-Evidence($obj,[string]$name) {
  $obj | ConvertTo-Json -Depth 50 | Set-Content -Encoding utf8 (Join-Path $OutDir $name)
}
$verdict = "INCONCLUSIVE"
try {
  $build=Read-Endpoint "/debug/build"
  $launch=Read-Endpoint "/debug/build94/launch"
  $execution=Read-Endpoint "/debug/execution"
  $telemetry=Read-Endpoint "/debug/telemetry"
  Save-Evidence $build "build.json"
  Save-Evidence $launch "launch.json"
  Save-Evidence $execution "execution.json"
  Save-Evidence $telemetry "telemetry.json"
  if ($build.build_id -ne "rc1.26-build96-native-k2-gdn-simd") { throw "Wrong build identity: $($build.build_id)" }
  if ([int]$launch.context_window -ne 32768) { throw "Expected 32768 context, got $($launch.context_window)" }
  if ($execution.schema -ne "bonsai-build94-execution-v1") { throw "Unknown execution schema" }
  if ([int]$execution.active_count -ne 0) { throw "Device is busy; refusing to schedule a new arm" }
  $arm=[string]$launch.active_arm
  $expected = switch ($arm) { "BASELINE8" { 8 } "CANDIDATE16" { 16 } "SAFE4" { 4 } default { 0 } }
  if ($expected -eq 0) { throw "No recognized active arm; process restart may be required" }
  $values=@(
    [int]$launch.active_batch, [int]$launch.active_ubatch,
    [int]$launch.engine_context_batch, [int]$launch.engine_context_ubatch
  )
  if (@($values | Where-Object { $_ -ne $expected }).Count -gt 0) {
    throw "Effective shape mismatch: arm=$arm, advertised=$($launch.active_batch)/$($launch.active_ubatch), engine=$($launch.engine_context_batch)/$($launch.engine_context_ubatch)"
  }
  if ($launch.sticky_fallback -eq $true -and $ScheduleNext -ne "" -and $ScheduleNext -ne "SAFE4") {
    throw "Sticky recovery detected; do not bypass without explicit recovery review"
  }
  $verdict = "PASS_PREFLIGHT_ONLY"
  if ($ScheduleNext) {
    $body = @{ arm=$ScheduleNext } | ConvertTo-Json -Compress
    $next=Invoke-RestMethod -Method Post -Uri "$base/debug/build94/next-launch" -Headers $headers -Body $body -TimeoutSec 20
    Save-Evidence $next "next-launch.json"
    if ($next.next_arm -ne $ScheduleNext) { throw "Server did not confirm requested next arm" }
    $verdict = "PASS_SCHEDULED_RESTART_REQUIRED"
  }
  Write-Host "Build96 K2: $verdict | active=$arm | batch=$expected/$expected"
  Write-Host "This is not a decode-speed or numerical-correctness certification."
} catch {
  $verdict="BLOCKED"
  $_.Exception.Message | Set-Content -Encoding utf8 (Join-Path $OutDir "error.txt")
  Write-Host "Build96 K2: BLOCKED - $($_.Exception.Message)"
} finally {
  $summary=[ordered]@{ captured_at=(Get-Date).ToString("o"); verdict=$verdict; required_build="rc1.26-build96-native-k2-gdn-simd"; scheduled_next=$ScheduleNext; device_test_certified=$false }
  Save-Evidence $summary "summary.json"
  $zip = "$OutDir.zip"
  if (Test-Path $zip) { Remove-Item -Force $zip }
  Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zip
  Write-Host "Evidence: $zip"
}
if ($verdict -eq "BLOCKED") { exit 2 }
