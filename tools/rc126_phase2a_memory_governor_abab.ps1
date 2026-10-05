param(
    [string]$BaseUrl = "http://192.168.1.85:8080/v1",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [int]$Cycles = 3,
    [string]$OutRoot = "D:\apple\re_output\rc126-phase2a1-memory-governor"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) { throw "PowerShell 7+ (pwsh.exe) is required." }
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Set BONSAI_API_KEY or pass -ApiKey." }
if ($Cycles -lt 2 -or $Cycles -gt 5) { throw "Cycles must be between 2 and 5." }

$root = $BaseUrl -replace "/v1/?$", ""
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutRoot $stamp
New-Item -ItemType Directory -Force -Path $out | Out-Null
$headers = @{ Authorization = "Bearer $ApiKey"; Accept = "application/json" }
$expectedText = "RC126_PHASE2A1_FIXED_OK"

function Save-Json([string]$Name, $Value) {
    $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $out "$Name.json") -Encoding utf8
}
function Get-Bonsai([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers
}
function Set-Variant([string]$Variant) {
    $governor = $Variant -eq "GOVERNOR"
    $profile = if ($governor) { "EXPERIMENTAL" } else { "BASELINE" }
    $body = @{
        profile = $profile
        flags = @{
            "bb.telemetry.extended" = $true
            "bb.governor.metalAware" = $governor
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
    Invoke-RestMethod -Method Post -Uri "$root/debug/runtime/profile" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
}
function Invoke-ExactText() {
    $body = @{
        model = "bonsai-2-27b-local"
        messages = @(@{ role = "user"; content = "Reply with exactly $expectedText" })
        max_tokens = 32
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Depth 10
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
    $sw.Stop()
    $text = ([string]$response.choices[0].message.content).Trim()
    if ($text -ne $expectedText) { throw "Text mismatch. Expected=$expectedText Actual=$text" }
    [pscustomobject]@{ elapsed_ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 3); text = $text; usage = $response.usage }
}

$healthStart = Get-Bonsai "/health"
$build = Get-Bonsai "/debug/build"
if ($build.build -ne "67") { throw "Expected Build 67, got $($build.build)." }
if ($build.build_id -ne "rc1.26-build67-request-lifecycle-governor-observer") { throw "Unexpected build_id: $($build.build_id)" }

# Unmeasured warmup removes first-request allocation noise from the A/B timing.
$null = Set-Variant "BASELINE"
$warmup = Invoke-ExactText
$warmTelemetry = Get-Bonsai "/debug/telemetry"
Save-Json "00_warmup" ([ordered]@{ text = $warmup; telemetry = $warmTelemetry })

$rows = @()
$ordinal = 0
for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
    foreach ($variant in @("BASELINE", "GOVERNOR")) {
        $ordinal += 1
        $runtime = Set-Variant $variant
        $before = Get-Bonsai "/debug/telemetry"
        $governorBefore = Get-Bonsai "/debug/governor"
        $sequenceBefore = [int]$governorBefore.request_observation_sequence

        if ($runtime.behavior_changes_enabled -ne $false) { throw "Behavior-changing feature became effective in $variant." }
        if ($variant -eq "BASELINE") {
            if ($runtime.effective.profile -ne "BASELINE") { throw "BASELINE did not remain effective BASELINE." }
            if ($governorBefore.observer_active -ne $false) { throw "Governor observer unexpectedly active in BASELINE." }
        } else {
            if ($runtime.effective.profile -ne "EXPERIMENTAL") { throw "GOVERNOR did not become effective EXPERIMENTAL." }
            if ($governorBefore.observer_active -ne $true) { throw "Governor observer not active in GOVERNOR variant." }
            if ($governorBefore.actuator_enabled -ne $false) { throw "Heap pressure actuator unexpectedly enabled." }
        }

        $text = Invoke-ExactText
        $after = Get-Bonsai "/debug/telemetry"
        $governorAfter = Get-Bonsai "/debug/governor"
        $sequenceAfter = [int]$governorAfter.request_observation_sequence
        $sequenceDelta = $sequenceAfter - $sequenceBefore

        if ($variant -eq "BASELINE" -and $sequenceDelta -ne 0) { throw "BASELINE unexpectedly recorded governor request boundaries." }
        if ($variant -eq "GOVERNOR") {
            if ($sequenceDelta -ne 2) { throw "GOVERNOR expected exactly 2 boundary samples, got $sequenceDelta." }
            if ($null -eq $governorAfter.last_request_begin -or $governorAfter.last_request_begin.stage -ne "API_REQUEST_BEGIN") { throw "Missing API_REQUEST_BEGIN evidence." }
            if ($null -eq $governorAfter.last_request_end -or $governorAfter.last_request_end.stage -ne "API_REQUEST_END") { throw "Missing API_REQUEST_END evidence." }
        }

        $row = [ordered]@{
            ordinal = $ordinal
            cycle = $cycle
            variant = $variant
            elapsed_ms = $text.elapsed_ms
            prompt_tokens = [int]$text.usage.prompt_tokens
            completion_tokens = [int]$text.usage.completion_tokens
            total_tokens = [int]$text.usage.total_tokens
            metal_before = $before.metal_allocated_bytes
            metal_after = $after.metal_allocated_bytes
            metal_delta = [int64]$after.metal_allocated_bytes - [int64]$before.metal_allocated_bytes
            headroom_before = $before.metal_headroom_bytes
            headroom_after = $after.metal_headroom_bytes
            available_before = $before.available_bytes
            available_after = $after.available_bytes
            phys_footprint_before = $before.phys_footprint_bytes
            phys_footprint_after = $after.phys_footprint_bytes
            thermal_before = $before.thermal_state
            thermal_after = $after.thermal_state
            governor_grade_before = $governorBefore.grade
            governor_grade_after = $governorAfter.grade
            governor_action_after = $governorAfter.recommended_action
            governor_reasons_after = @($governorAfter.reasons)
            governor_sequence_before = $sequenceBefore
            governor_sequence_after = $sequenceAfter
            governor_sequence_delta = $sequenceDelta
            last_request_begin = $governorAfter.last_request_begin
            last_request_end = $governorAfter.last_request_end
            behavior_changes_enabled = $runtime.behavior_changes_enabled
        }
        $rows += [pscustomobject]$row
        Save-Json ("run_{0:D2}_{1}" -f $ordinal, $variant.ToLowerInvariant()) $row
    }
}

$restored = Set-Variant "BASELINE"
if ($restored.effective.profile -ne "BASELINE") { throw "Unable to restore BASELINE profile." }
$healthEnd = Get-Bonsai "/health"

$promptTokenKinds = @($rows.prompt_tokens | Sort-Object -Unique)
$completionTokenKinds = @($rows.completion_tokens | Sort-Object -Unique)
$totalTokenKinds = @($rows.total_tokens | Sort-Object -Unique)
$fixtureValid = ($promptTokenKinds.Count -eq 1 -and $completionTokenKinds.Count -eq 1 -and $totalTokenKinds.Count -eq 1)

$baseline = @($rows | Where-Object variant -eq "BASELINE")
$governor = @($rows | Where-Object variant -eq "GOVERNOR")
$baselineAvg = ($baseline | Measure-Object elapsed_ms -Average).Average
$governorAvg = ($governor | Measure-Object elapsed_ms -Average).Average
$overheadPct = if ($baselineAvg -gt 0) { (($governorAvg - $baselineAvg) / $baselineAvg) * 100.0 } else { 0.0 }
$unsafeThermal = @($rows | Where-Object { $_.thermal_before -in @("serious", "critical") -or $_.thermal_after -in @("serious", "critical") })
$invalidBehavior = @($rows | Where-Object behavior_changes_enabled -ne $false)
$badGovernorEvidence = @($rows | Where-Object { ($_.variant -eq "BASELINE" -and $_.governor_sequence_delta -ne 0) -or ($_.variant -eq "GOVERNOR" -and $_.governor_sequence_delta -ne 2) })

$overall = if ($fixtureValid -and $unsafeThermal.Count -eq 0 -and $invalidBehavior.Count -eq 0 -and $badGovernorEvidence.Count -eq 0 -and $healthEnd.status -eq "ok") { "PASS" } else { "FAIL" }
$decision = if (-not $fixtureValid) { "INVALID_FIXTURE" } elseif ($overall -ne "PASS") { "REJECT" } elseif ($overheadPct -gt 10.0) { "REJECT_OBSERVER_OVERHEAD" } elseif ($overheadPct -gt 5.0) { "HOLD_OBSERVER_OVERHEAD" } else { "OBSERVER_ONLY_PASS" }

$summary = [ordered]@{
    overall = $overall
    decision = $decision
    phase = "RC1.26_PHASE2A1_REQUEST_LIFECYCLE_OBSERVER"
    timestamp = $stamp
    cycles = $Cycles
    run_count = $rows.Count
    base_url = $BaseUrl
    build = $build
    fixture_valid = $fixtureValid
    prompt_token_values = $promptTokenKinds
    completion_token_values = $completionTokenKinds
    total_token_values = $totalTokenKinds
    baseline_average_ms = [math]::Round($baselineAvg, 3)
    governor_average_ms = [math]::Round($governorAvg, 3)
    governor_overhead_percent = [math]::Round($overheadPct, 3)
    unsafe_thermal_count = $unsafeThermal.Count
    behavior_change_count = $invalidBehavior.Count
    bad_governor_evidence_count = $badGovernorEvidence.Count
    restored_profile = $restored.effective.profile
    health_start = $healthStart.status
    health_end = $healthEnd.status
    warmup = $warmup
    rows = $rows
}
Save-Json "summary" $summary

if ($overall -ne "PASS") { throw "Phase 2A.1 campaign failed. Decision=$decision See $out\summary.json" }
Write-Host "[PASS] RC1.26 Phase 2A.1 Request Lifecycle Governor ABAB"
Write-Host "Decision: $decision"
Write-Host "Governor observer overhead: $([math]::Round($overheadPct, 3))%"
Write-Host "Fixture tokens: prompt=$($promptTokenKinds -join ',') completion=$($completionTokenKinds -join ',')"
Write-Host "Restored profile: $($restored.effective.profile)"
Write-Host "Output: $out"
