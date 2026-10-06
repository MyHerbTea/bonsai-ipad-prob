param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [Parameter(Mandatory = $true)]
    [ValidateSet("BASELINE16", "CANDIDATE32")]
    [string]$Arm,
    [ValidateSet("", "BASELINE16", "CANDIDATE32")]
    [string]$NextArm = "",
    [string]$OutDir = "",
    [string]$ExpectedBuildId = "rc1.26-build73-prefill-batch-16-vs-32"
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
$apiRoot = "$root/v1"

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Get-Location) "re_output/rc126-phase2e-$($Arm.ToLower())-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$headers = @{
    Authorization = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}

function Get-BonsaiJson([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers
}

function Post-BonsaiJson([string]$Path, [hashtable]$Body) {
    Invoke-RestMethod -Method Post -Uri "$root$Path" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 20)
}

function Save-Json($Value, [string]$Name) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -Encoding utf8 (Join-Path $OutDir $Name)
}

$build = Get-BonsaiJson "/debug/build"
$launch = Get-BonsaiJson "/debug/phase2e/launch"
$prefillBefore = Get-BonsaiJson "/debug/prefill"
$telemetryBefore = Get-BonsaiJson "/debug/telemetry"

Save-Json $build "build.json"
Save-Json $launch "launch-before.json"
Save-Json $prefillBefore "prefill-before.json"
Save-Json $telemetryBefore "telemetry-before.json"

if ($build.build_id -ne $ExpectedBuildId) {
    throw "Unexpected build_id: $($build.build_id)"
}
if ($launch.phase -ne "RC1.26_PHASE2E_PREFILL_BATCH_16_VS_32_VIABILITY") {
    throw "Unexpected Phase 2E phase: $($launch.phase)"
}
if ($launch.launch_arm -ne $Arm) {
    throw "Wrong launch arm. Expected $Arm, got $($launch.launch_arm). Restart the app after scheduling the requested arm."
}
if ($launch.shape_evidence_valid -ne $true) {
    throw "Runtime batch/ubatch do not match the launch arm."
}
$expected = if ($Arm -eq "CANDIDATE32") { 32 } else { 16 }
if ([int]$launch.active_batch -ne $expected -or [int]$launch.active_ubatch -ne $expected) {
    throw "Active batch shape mismatch. Expected $expected/$expected, got $($launch.active_batch)/$($launch.active_ubatch)."
}
if ($launch.metal_tensor_forced_baseline -ne $true -or $launch.ggml_metal_tensor_disable -ne "1") {
    throw "Phase 2E isolation violation: Metal Tensor is not forced to baseline."
}

$promptUnit = "alpha beta gamma delta epsilon zeta eta theta "
$prompt = "Read the following deterministic token sequence and answer only with the word OK. " + ($promptUnit * 64)

$body = @{
    model = "bonsai-2-27b-local"
    messages = @(
        @{
            role = "user"
            content = $prompt
        }
    )
    max_tokens = 16
    temperature = 0
    top_p = 1
    seed = 424242
    stream = $false
}

function Invoke-Measurement([string]$Label, [bool]$Included) {
    Write-Host "Running $Label ..."
    $response = Invoke-RestMethod -Method Post -Uri "$apiRoot/chat/completions" -Headers $headers -Body ($body | ConvertTo-Json -Depth 20)
    $prefill = Get-BonsaiJson "/debug/prefill"
    $answer = [string]$response.choices[0].message.content
    $answerBytes = [System.Text.Encoding]::UTF8.GetBytes($answer)
    $answerHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($answerBytes)).ToLowerInvariant()

    [pscustomobject][ordered]@{
        label = $Label
        included = $Included
        sequence = [int]$prefill.last.sequence
        prompt_tokens = [int]$prefill.last.prompt_tokens
        completion_tokens = [int]$prefill.last.completion_tokens
        prefill_ms = [double]$prefill.last.prefill_ms
        decode_to_first_token_ms = [double]$prefill.last.decode_to_first_token_ms
        ttft_ms = [double]$prefill.last.ttft_ms
        tokens_per_second = [double]$prefill.last.tokens_per_second
        answer_sha256 = $answerHash
        answer = $answer
    }
}

$all = @()
$all += Invoke-Measurement "warmup" $false
1..2 | ForEach-Object {
    $all += Invoke-Measurement "measure_$_" $true
}
$all | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $OutDir "measurements.json")

$measured = @($all | Where-Object { $_.included })
$promptTokens = @($measured.prompt_tokens | Sort-Object -Unique)
$answerHashes = @($measured.answer_sha256 | Sort-Object -Unique)
if ($promptTokens.Count -ne 1) {
    throw "Prompt token count changed within arm."
}
if ($answerHashes.Count -ne 1) {
    throw "Deterministic answer changed within arm."
}

$telemetryAfter = Get-BonsaiJson "/debug/telemetry"
$launchAfter = Get-BonsaiJson "/debug/phase2e/launch"
Save-Json $telemetryAfter "telemetry-after.json"
Save-Json $launchAfter "launch-after.json"

$summary = [ordered]@{
    captured_at = (Get-Date).ToString("o")
    build_id = $build.build_id
    phase = $launch.phase
    arm = $Arm
    process_launch_id = $launch.process_launch_id
    batch = [int]$launch.active_batch
    ubatch = [int]$launch.active_ubatch
    prompt_tokens = [int]$promptTokens[0]
    answer_sha256 = [string]$answerHashes[0]
    measured_samples = $measured.Count
    avg_prefill_ms = [double](($measured.prefill_ms | Measure-Object -Average).Average)
    avg_decode_to_first_token_ms = [double](($measured.decode_to_first_token_ms | Measure-Object -Average).Average)
    avg_ttft_ms = [double](($measured.ttft_ms | Measure-Object -Average).Average)
    avg_tokens_per_second = [double](($measured.tokens_per_second | Measure-Object -Average).Average)
    next_launch_arm_requested = $NextArm
}
Save-Json $summary "summary.json"

if (-not [string]::IsNullOrWhiteSpace($NextArm)) {
    $scheduled = Post-BonsaiJson "/debug/phase2e/next-launch" @{ arm = $NextArm }
    Save-Json $scheduled "next-launch.json"
    if ($scheduled.next_launch_arm -ne $NextArm) {
        throw "Failed to schedule next arm $NextArm."
    }
}

$zipPath = "$OutDir.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath

Write-Host ""
Write-Host "Phase 2E prefill batch arm: PASS"
Write-Host "Arm: $Arm"
Write-Host "Batch/UBatch: $expected/$expected"
Write-Host ("Avg prefill ms: {0:N3}" -f $summary.avg_prefill_ms)
Write-Host ("Avg TTFT ms: {0:N3}" -f $summary.avg_ttft_ms)
Write-Host ("Avg tok/s: {0:N3}" -f $summary.avg_tokens_per_second)
if (-not [string]::IsNullOrWhiteSpace($NextArm)) {
    Write-Host "Next launch arm: $NextArm"
}
Write-Host "Evidence: $zipPath"
