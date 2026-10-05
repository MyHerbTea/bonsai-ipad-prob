param(
    [string]$BaseUrl = "http://192.168.0.102:8080/v1",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [int]$Cycles = 3,
    [string]$OutRoot = "D:\\apple\\re_output\\rc126-phase2b-heap-pressure-relief"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) { throw "PowerShell 7+ is required." }
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Set BONSAI_API_KEY or pass -ApiKey." }
if ($Cycles -lt 2 -or $Cycles -gt 5) { throw "Cycles must be between 2 and 5." }

$root = $BaseUrl -replace "/v1/?$", ""
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutRoot $stamp
New-Item -ItemType Directory -Force -Path $out | Out-Null
$headers = @{ Authorization = "Bearer $ApiKey"; Accept = "application/json" }
$expectedPrimary = "RC126_PHASE2B_FIXED_OK"
$expectedPostTrim = "RC126_PHASE2B_POST_TRIM_OK"

function Save-Json([string]$Name, $Value) {
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $out "$Name.json") -Encoding utf8
}
function Get-Bonsai([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers
}
function Set-Variant([string]$Variant) {
    $relief = $Variant -eq "RELIEF"
    $profile = if ($relief) { "EXPERIMENTAL" } else { "BASELINE" }
    $body = @{
        profile = $profile
        flags = @{
            "bb.telemetry.extended" = $true
            "bb.governor.metalAware" = $relief
            "bb.heapPressureRelief" = $relief
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
    Invoke-RestMethod -Method Post -Uri "$root/debug/runtime/profile" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
}
function Invoke-ExactText([string]$Expected) {
    $body = @{
        model = "bonsai-2-27b-local"
        messages = @(@{ role = "user"; content = "Reply with exactly $Expected" })
        max_tokens = 32
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Depth 10
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
    $sw.Stop()
    $text = ([string]$response.choices[0].message.content).Trim()
    if ($text -ne $Expected) { throw "Text mismatch. Expected=$Expected Actual=$text" }
    [pscustomobject]@{
        elapsed_ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 3)
        text = $text
        usage = $response.usage
    }
}
function Invoke-ForcedTrim() {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$root/debug/gc-or-trim" -Headers $headers -ContentType "application/json; charset=utf-8" -Body "{}"
    $sw.Stop()
    [pscustomobject]@{
        endpoint_elapsed_ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 3)
        response = $response
    }
}

$healthStart = Get-Bonsai "/health"
$build = Get-Bonsai "/debug/build"
if ($build.build -ne "68") { throw "Expected Build 68, got $($build.build)." }
if ($build.build_id -ne "rc1.26-build68-heap-pressure-relief") { throw "Unexpected build_id: $($build.build_id)" }

$null = Set-Variant "BASELINE"
$warmup = Invoke-ExactText $expectedPrimary
Save-Json "00_warmup" $warmup

$rows = @()
$ordinal = 0
for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
    foreach ($variant in @("BASELINE", "RELIEF")) {
        $ordinal += 1
        $runtime = Set-Variant $variant
        $before = Get-Bonsai "/debug/telemetry"
        $governorBefore = Get-Bonsai "/debug/governor"
        $seqBefore = [int]$governorBefore.request_observation_sequence

        if ($variant -eq "BASELINE") {
            if ($runtime.effective.profile -ne "BASELINE") { throw "BASELINE profile mismatch." }
            if ($runtime.behavior_changes_enabled -ne $false) { throw "Behavior change enabled in BASELINE." }
            if ($runtime.effective.flags."bb.heapPressureRelief" -ne $false) { throw "Relief effective in BASELINE." }
        } else {
            if ($runtime.effective.profile -ne "EXPERIMENTAL") { throw "RELIEF profile mismatch." }
            if ($runtime.behavior_changes_enabled -ne $true) { throw "RELIEF actuator did not become behavior-changing effective." }
            if ($runtime.effective.flags."bb.governor.metalAware" -ne $true) { throw "Governor not effective." }
            if ($runtime.effective.flags."bb.heapPressureRelief" -ne $true) { throw "Heap relief not effective." }
        }

        $primary = Invoke-ExactText $expectedPrimary
        $afterPrimary = Get-Bonsai "/debug/telemetry"
        $governorAfterPrimary = Get-Bonsai "/debug/governor"
        $seqAfterPrimary = [int]$governorAfterPrimary.request_observation_sequence
        $seqDelta = $seqAfterPrimary - $seqBefore

        if ($variant -eq "BASELINE" -and $seqDelta -ne 0) { throw "BASELINE unexpectedly observed request boundaries." }
        if ($variant -eq "RELIEF" -and $seqDelta -ne 2) { throw "RELIEF expected 2 observer boundaries, got $seqDelta." }

        $trim = $null
        $postTrim = $null
        $afterTrim = $null
        if ($variant -eq "RELIEF") {
            $trim = Invoke-ForcedTrim
            if ($trim.response.result.performed -ne $true) { throw "Forced trim was not performed." }
            if ($trim.response.result.reason -ne "debug_forced") { throw "Unexpected trim reason." }
            $afterTrim = Get-Bonsai "/debug/telemetry"
            $postTrim = Invoke-ExactText $expectedPostTrim
        }

        $row = [ordered]@{
            ordinal = $ordinal
            cycle = $cycle
            variant = $variant
            primary_elapsed_ms = $primary.elapsed_ms
            prompt_tokens = [int]$primary.usage.prompt_tokens
            completion_tokens = [int]$primary.usage.completion_tokens
            total_tokens = [int]$primary.usage.total_tokens
            observer_sequence_delta = $seqDelta
            metal_before = $before.metal_allocated_bytes
            metal_after_primary = $afterPrimary.metal_allocated_bytes
            phys_footprint_before = $before.phys_footprint_bytes
            phys_footprint_after_primary = $afterPrimary.phys_footprint_bytes
            available_before = $before.available_bytes
            available_after_primary = $afterPrimary.available_bytes
            thermal_before = $before.thermal_state
            thermal_after_primary = $afterPrimary.thermal_state
            governor_grade = $governorAfterPrimary.grade
            automatic_relief = $governorAfterPrimary.last_heap_pressure_relief
            forced_trim = if ($null -ne $trim) { $trim.response.result } else { $null }
            forced_trim_endpoint_elapsed_ms = if ($null -ne $trim) { $trim.endpoint_elapsed_ms } else { $null }
            telemetry_after_trim = $afterTrim
            post_trim_text = if ($null -ne $postTrim) { $postTrim.text } else { $null }
            post_trim_elapsed_ms = if ($null -ne $postTrim) { $postTrim.elapsed_ms } else { $null }
            behavior_changes_enabled = $runtime.behavior_changes_enabled
        }
        $rows += [pscustomobject]$row
        Save-Json ("run_{0:D2}_{1}" -f $ordinal, $variant.ToLowerInvariant()) $row
    }
}

$restored = Set-Variant "BASELINE"
if ($restored.effective.profile -ne "BASELINE") { throw "Unable to restore BASELINE." }
$healthEnd = Get-Bonsai "/health"

$promptKinds = @($rows.prompt_tokens | Sort-Object -Unique)
$completionKinds = @($rows.completion_tokens | Sort-Object -Unique)
$totalKinds = @($rows.total_tokens | Sort-Object -Unique)
$fixtureValid = $promptKinds.Count -eq 1 -and $completionKinds.Count -eq 1 -and $totalKinds.Count -eq 1

$baselineRows = @($rows | Where-Object variant -eq "BASELINE")
$reliefRows = @($rows | Where-Object variant -eq "RELIEF")
$baselineAvg = ($baselineRows | Measure-Object primary_elapsed_ms -Average).Average
$reliefAvg = ($reliefRows | Measure-Object primary_elapsed_ms -Average).Average
$observerOverheadPct = if ($baselineAvg -gt 0) { (($reliefAvg - $baselineAvg) / $baselineAvg) * 100.0 } else { 0.0 }

$bytesReleased = @($reliefRows | ForEach-Object { [int64]$_.forced_trim.bytes_released })
$trimDurations = @($reliefRows | ForEach-Object { [double]$_.forced_trim.duration_ms })
$totalBytesReleased = ($bytesReleased | Measure-Object -Sum).Sum
$maxTrimDuration = ($trimDurations | Measure-Object -Maximum).Maximum

$unsafeThermal = @($rows | Where-Object { $_.thermal_before -in @("serious", "critical") -or $_.thermal_after_primary -in @("serious", "critical") })
$badPostTrim = @($reliefRows | Where-Object post_trim_text -ne $expectedPostTrim)
$badBehavior = @($baselineRows | Where-Object behavior_changes_enabled -ne $false)
$badBehavior += @($reliefRows | Where-Object behavior_changes_enabled -ne $true)

$overall = if ($fixtureValid -and $unsafeThermal.Count -eq 0 -and $badPostTrim.Count -eq 0 -and $badBehavior.Count -eq 0 -and $healthEnd.status -eq "ok") { "PASS" } else { "FAIL" }

$decision = if ($overall -ne "PASS") {
    "REJECT"
} elseif ($maxTrimDuration -gt 1000.0) {
    "REJECT_RELIEF_STALL"
} elseif ($maxTrimDuration -gt 250.0) {
    "HOLD_RELIEF_LATENCY"
} elseif ($totalBytesReleased -le 0) {
    "SAFE_NO_RECLAIM_OBSERVED"
} else {
    "HEAP_RELIEF_CANDIDATE_PASS"
}

$summary = [ordered]@{
    overall = $overall
    decision = $decision
    phase = "RC1.26_PHASE2B_HEAP_PRESSURE_RELIEF"
    timestamp = $stamp
    cycles = $Cycles
    run_count = $rows.Count
    base_url = $BaseUrl
    build = $build
    fixture_valid = $fixtureValid
    prompt_token_values = $promptKinds
    completion_token_values = $completionKinds
    total_token_values = $totalKinds
    baseline_average_ms = [math]::Round($baselineAvg, 3)
    relief_average_ms = [math]::Round($reliefAvg, 3)
    observer_overhead_percent = [math]::Round($observerOverheadPct, 3)
    total_bytes_released = [int64]$totalBytesReleased
    max_trim_duration_ms = [math]::Round($maxTrimDuration, 3)
    unsafe_thermal_count = $unsafeThermal.Count
    post_trim_failure_count = $badPostTrim.Count
    restored_profile = $restored.effective.profile
    health_start = $healthStart.status
    health_end = $healthEnd.status
    warmup = $warmup
    rows = $rows
}
Save-Json "summary" $summary

if ($overall -ne "PASS") { throw "Phase 2B failed. Decision=$decision See $out\\summary.json" }

Write-Host "[PASS] RC1.26 Phase 2B Heap Pressure Relief"
Write-Host "Decision: $decision"
Write-Host "Total allocator bytes released: $totalBytesReleased"
Write-Host "Max native trim duration: $([math]::Round($maxTrimDuration, 3)) ms"
Write-Host "Restored profile: $($restored.effective.profile)"
Write-Host "Output: $out"
