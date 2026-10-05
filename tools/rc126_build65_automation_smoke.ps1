param(
    [string]$BaseUrl = "http://192.168.1.85:8080/v1",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [string]$OutRoot = "D:\\apple\\re_output\\rc126-build65-automation-smoke"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) { throw "PowerShell 7+ (pwsh.exe) is required." }
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Set BONSAI_API_KEY or pass -ApiKey." }

$root = $BaseUrl -replace "/v1/?$", ""
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutRoot $stamp
New-Item -ItemType Directory -Force -Path $out | Out-Null
$headers = @{ Authorization = "Bearer $ApiKey"; Accept = "application/json" }

function Save-Json([string]$Name, $Value) {
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $out "$Name.json") -Encoding utf8
}
function Get-Bonsai([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers
}

$health = Get-Bonsai "/health"
$build = Get-Bonsai "/debug/build"
$runtimeBefore = Get-Bonsai "/debug/runtime"
$telemetry = Get-Bonsai "/debug/telemetry"

$profileBody = @{
    profile = "BASELINE"
    flags = @{
        "bb.telemetry.extended" = $true
        "bb.governor.metalAware" = $false
        "bb.heapPressureRelief" = $false
        "bb.metalTensor.prefill" = $false
        "bb.metalFusion.experimental" = $false
        "bb.lazyEmbedding" = $false
        "bb.prefixStateCache" = $false
        "bb.tieredKV" = $false
        "bb.tieredKV.quantizedCold" = $false
        "bb.aneColdKV" = $false
        "bb.speculative.experimental" = $false
    }
} | ConvertTo-Json -Depth 10
$runtimeAfter = Invoke-RestMethod -Method Post -Uri "$root/debug/runtime/profile" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $profileBody

if ($runtimeAfter.effective.profile -ne "BASELINE") { throw "Effective profile is not BASELINE." }
if ($runtimeAfter.behavior_changes_enabled -ne $false) { throw "Behavior-changing optimization unexpectedly enabled." }

$textBody = @{
    model = "bonsai-2-27b-local"
    messages = @(@{ role = "user"; content = "Reply with exactly RC126_AUTOMATION_TEXT_OK" })
    max_tokens = 32
    temperature = 0
    stream = $false
} | ConvertTo-Json -Depth 10
$text = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $textBody
$textValue = [string]$text.choices[0].message.content
if ($textValue.Trim() -ne "RC126_AUTOMATION_TEXT_OK") { throw "Text smoke mismatch: $textValue" }

Save-Json "01_health" $health
Save-Json "02_build" $build
Save-Json "03_runtime_before" $runtimeBefore
Save-Json "04_telemetry" $telemetry
Save-Json "05_runtime_after" $runtimeAfter
Save-Json "06_text" $text

$summary = [ordered]@{
    overall = "PASS"
    timestamp = $stamp
    base_url = $BaseUrl
    build = $build
    effective_profile = $runtimeAfter.effective.profile
    behavior_changes_enabled = $runtimeAfter.behavior_changes_enabled
    thermal_state = $telemetry.thermal_state
    metal_allocated_bytes = $telemetry.metal_allocated_bytes
    metal_recommended_working_set_bytes = $telemetry.metal_recommended_working_set_bytes
    metal_headroom_bytes = $telemetry.metal_headroom_bytes
    text = $textValue.Trim()
}
Save-Json "summary" $summary
Write-Host "[PASS] RC1.26 Build 65 automation smoke"
Write-Host "Output: $out"
