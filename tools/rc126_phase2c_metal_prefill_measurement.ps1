param(
    [string]$BaseUrl = "http://192.168.0.102:8080/v1",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [int]$Cycles = 3,
    [string]$OutRoot = "D:\\apple\\re_output\\rc126-phase2c-metal-prefill-measurement"
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
$expected = "RC126_PHASE2C_PREFILL_OK"
$fillerUnit = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu "
$filler = $fillerUnit * 40
$prompt = $filler + [Environment]::NewLine + "Ignore the filler above. Reply with exactly $expected"

function Save-Json([string]$Name, $Value) {
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $out "$Name.json") -Encoding utf8
}
function Get-Bonsai([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers
}
function Set-Baseline() {
    $body = @{
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
    Invoke-RestMethod -Method Post -Uri "$root/debug/runtime/profile" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
}
function Invoke-PrefillFixture() {
    $body = @{
        model = "bonsai-2-27b-local"
        messages = @(@{ role = "user"; content = $prompt })
        max_tokens = 32
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Depth 10
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
    $sw.Stop()
    $text = ([string]$response.choices[0].message.content).Trim()
    if ($text -ne $expected) { throw "Text mismatch. Expected=$expected Actual=$text" }
    [pscustomobject]@{ elapsed_ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 3); text = $text; usage = $response.usage }
}

$healthStart = Get-Bonsai "/health"
$build = Get-Bonsai "/debug/build"
if ($build.build -ne "69") { throw "Expected Build 69, got $($build.build)." }
if ($build.build_id -ne "rc1.26-build69-metal-prefill-measurement") { throw "Unexpected build_id: $($build.build_id)" }

$runtime = Set-Baseline
if ($runtime.effective.profile -ne "BASELINE") { throw "Unable to establish BASELINE." }
if ($runtime.behavior_changes_enabled -ne $false) { throw "Behavior-changing feature effective in measurement baseline." }

$capability = Get-Bonsai "/debug/prefill"
if ($capability.phase -ne "RC1.26_PHASE2C_METAL_PREFILL_MEASUREMENT") { throw "Unexpected prefill phase." }
if ($capability.metal_tensor_prefill_effective -ne $false) { throw "Metal Tensor unexpectedly effective." }
if ([string]$capability.ggml_metal_tensor_disable -ne "1") { throw "Frozen GGML_METAL_TENSOR_DISABLE=1 workaround is not active." }
Save-Json "00_capability" $capability

$warm = Invoke-PrefillFixture
$warmPrefill = Get-Bonsai "/debug/prefill"
Save-Json "01_warmup" ([ordered]@{ request = $warm; prefill = $warmPrefill })

$rows = @()
$previousSequence = [int]$warmPrefill.last.sequence
for ($i = 1; $i -le $Cycles; $i++) {
    $before = Get-Bonsai "/debug/telemetry"
    $request = Invoke-PrefillFixture
    $after = Get-Bonsai "/debug/telemetry"
    $prefill = Get-Bonsai "/debug/prefill"

    if ($prefill.measurement_ready -ne $true) { throw "Prefill measurement not ready." }
    if ($prefill.metal_tensor_prefill_effective -ne $false) { throw "Metal Tensor unexpectedly effective during baseline measurement." }
    if ([int]$prefill.last.sequence -ne ($previousSequence + 1)) { throw "Expected exactly one prefill observation per request." }
    $previousSequence = [int]$prefill.last.sequence
    if ([double]$prefill.last.prefill_ms -le 0) { throw "prefill_ms must be > 0." }
    if ([double]$prefill.last.decode_to_first_token_ms -lt 0) { throw "decode_to_first_token_ms must be >= 0." }
    if ([double]$prefill.last.ttft_ms -lt [double]$prefill.last.prefill_ms) { throw "TTFT cannot be less than prefill." }
    if ([double]$prefill.last.ttft_reconstruction_error_ms -gt 0.05) { throw "TTFT reconstruction error too large." }
    if ([int]$prefill.last.prompt_tokens -ne [int]$request.usage.prompt_tokens) { throw "Prompt token mismatch." }
    if ([int]$prefill.last.completion_tokens -ne [int]$request.usage.completion_tokens) { throw "Completion token mismatch." }

    $prefillTPS = [double]$prefill.last.prompt_tokens / ([double]$prefill.last.prefill_ms / 1000.0)
    $row = [ordered]@{
        cycle = $i
        elapsed_ms = $request.elapsed_ms
        prompt_tokens = [int]$request.usage.prompt_tokens
        completion_tokens = [int]$request.usage.completion_tokens
        total_tokens = [int]$request.usage.total_tokens
        prefill_ms = [double]$prefill.last.prefill_ms
        prefill_tokens_per_second = [math]::Round($prefillTPS, 3)
        decode_to_first_token_ms = [double]$prefill.last.decode_to_first_token_ms
        ttft_ms = [double]$prefill.last.ttft_ms
        ttft_reconstruction_error_ms = [double]$prefill.last.ttft_reconstruction_error_ms
        decode_tokens_per_second = [double]$prefill.last.tokens_per_second
        thermal_before = $before.thermal_state
        thermal_after = $after.thermal_state
        available_before = $before.available_bytes
        available_after = $after.available_bytes
        phys_footprint_before = $before.phys_footprint_bytes
        phys_footprint_after = $after.phys_footprint_bytes
        metal_before = $before.metal_allocated_bytes
        metal_after = $after.metal_allocated_bytes
    }
    $rows += [pscustomobject]$row
    Save-Json ("run_{0:D2}" -f $i) $row
}

$restored = Set-Baseline
$healthEnd = Get-Bonsai "/health"
$promptKinds = @($rows.prompt_tokens | Sort-Object -Unique)
$completionKinds = @($rows.completion_tokens | Sort-Object -Unique)
$totalKinds = @($rows.total_tokens | Sort-Object -Unique)
$fixtureValid = $promptKinds.Count -eq 1 -and $completionKinds.Count -eq 1 -and $totalKinds.Count -eq 1
$unsafeThermal = @($rows | Where-Object { $_.thermal_before -in @("serious","critical") -or $_.thermal_after -in @("serious","critical") })
$prefillAvg = ($rows | Measure-Object prefill_ms -Average).Average
$prefillMin = ($rows | Measure-Object prefill_ms -Minimum).Minimum
$prefillMax = ($rows | Measure-Object prefill_ms -Maximum).Maximum
$prefillTPSAvg = ($rows | Measure-Object prefill_tokens_per_second -Average).Average
$ttftAvg = ($rows | Measure-Object ttft_ms -Average).Average
$decodeFirstAvg = ($rows | Measure-Object decode_to_first_token_ms -Average).Average
$metalKinds = @($rows.metal_before + $rows.metal_after | Sort-Object -Unique)
$overall = if ($fixtureValid -and $unsafeThermal.Count -eq 0 -and $healthEnd.status -eq "ok" -and $restored.effective.profile -eq "BASELINE") { "PASS" } else { "FAIL" }
$decision = if ($overall -eq "PASS") { "PREFILL_MEASUREMENT_GATE_PASS" } else { "REJECT" }

$summary = [ordered]@{
    overall = $overall
    decision = $decision
    phase = "RC1.26_PHASE2C_METAL_PREFILL_MEASUREMENT"
    timestamp = $stamp
    cycles = $Cycles
    build = $build
    capability = $capability
    fixture_valid = $fixtureValid
    prompt_token_values = $promptKinds
    completion_token_values = $completionKinds
    total_token_values = $totalKinds
    prefill_average_ms = [math]::Round($prefillAvg, 3)
    prefill_min_ms = [math]::Round($prefillMin, 3)
    prefill_max_ms = [math]::Round($prefillMax, 3)
    prefill_tokens_per_second_average = [math]::Round($prefillTPSAvg, 3)
    decode_to_first_token_average_ms = [math]::Round($decodeFirstAvg, 3)
    ttft_average_ms = [math]::Round($ttftAvg, 3)
    metal_allocated_values = $metalKinds
    unsafe_thermal_count = $unsafeThermal.Count
    health_start = $healthStart.status
    health_end = $healthEnd.status
    restored_profile = $restored.effective.profile
    rows = $rows
}
Save-Json "summary" $summary
if ($overall -ne "PASS") { throw "Phase 2C measurement failed. See $out\summary.json" }
Write-Host "[PASS] RC1.26 Phase 2C Metal Prefill Measurement"
Write-Host "Decision: $decision"
Write-Host "Prompt tokens: $($promptKinds -join ',')"
Write-Host "Average prefill: $([math]::Round($prefillAvg, 3)) ms"
Write-Host "Average prefill throughput: $([math]::Round($prefillTPSAvg, 3)) tok/s"
Write-Host "Average decode->first-token: $([math]::Round($decodeFirstAvg, 3)) ms"
Write-Host "Average TTFT: $([math]::Round($ttftAvg, 3)) ms"
Write-Host "Restored profile: $($restored.effective.profile)"
Write-Host "Output: $out"
