param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [Parameter(Mandatory = $true)]
    [ValidateSet("BASELINE", "CANDIDATE")]
    [string]$Arm,
    [ValidateSet("", "BASELINE", "CANDIDATE")]
    [string]$NextArm = "",
    [string]$OutDir = "",
    [string]$ExpectedBuildId = "rc1.26-build71-fresh-backend-metal-tensor-ab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "API key is required. Set BONSAI_API_KEY or pass -ApiKey."
}

$root = $BaseUrl.TrimEnd("/")
if ($root.EndsWith("/v1")) {
    $root = $root.Substring(0, $root.Length - 3)
}
$apiRoot = "$root/v1"

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Get-Location) "re_output/rc126-phase2c1-$($Arm.ToLower())-$stamp"
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
$launch = Get-BonsaiJson "/debug/phase2c/launch"
$prefillBefore = Get-BonsaiJson "/debug/prefill"
$runtime = Get-BonsaiJson "/debug/runtime"
$health = Get-BonsaiJson "/health"
$telemetryBefore = Get-BonsaiJson "/debug/telemetry"

Save-Json $build "build.json"
Save-Json $launch "launch-before.json"
Save-Json $prefillBefore "prefill-before.json"
Save-Json $runtime "runtime.json"
Save-Json $health "health.json"
Save-Json $telemetryBefore "telemetry-before.json"

if ($build.build_id -ne $ExpectedBuildId) {
    throw "Unexpected build_id: $($build.build_id)"
}
if ($launch.phase -ne "RC1.26_PHASE2C1_FRESH_BACKEND_VIABILITY") {
    throw "Unexpected Phase 2C phase: $($launch.phase)"
}
if ($launch.launch_arm -ne $Arm) {
    throw "Wrong launch arm. Expected $Arm, got $($launch.launch_arm). Restart the app after scheduling the requested arm."
}
if ($launch.backend_latched_arm -ne $Arm) {
    throw "Backend arm mismatch. Expected $Arm, got $($launch.backend_latched_arm)."
}
if ($launch.backend_log_observed -ne $true) {
    throw "Active backend evidence missing: Prism has_tensor log was not observed."
}
if ($launch.backend_evidence_valid -ne $true) {
    throw "Active backend evidence is not valid for the current launch arm."
}
if ($launch.runtime_toggle_safe -ne $false) {
    throw "Safety violation: runtime toggle must remain unsafe."
}
if ($launch.requires_process_restart_between_arms -ne $true) {
    throw "Safety violation: process restart requirement missing."
}
if ($launch.metal_tensor_prefill_dispatch_proven -ne $false) {
    throw "Overclaim detected: dispatch must remain unproven in Phase 2C-1."
}

if ($Arm -eq "BASELINE") {
    if ($launch.backend_has_tensor -ne $false) {
        throw "BASELINE must prove backend has_tensor=false."
    }
    if ($launch.ggml_metal_tensor_disable -ne "1") {
        throw "BASELINE must retain GGML_METAL_TENSOR_DISABLE=1."
    }
} else {
    if ($launch.backend_has_tensor -ne $true) {
        throw "CANDIDATE must prove backend has_tensor=true."
    }
    if ($launch.ggml_metal_tensor_disable -ne "unset") {
        throw "CANDIDATE must start with GGML_METAL_TENSOR_DISABLE unset."
    }
}

$promptUnit = "alpha beta gamma delta epsilon zeta eta theta "
$prompt = "Read the following deterministic token sequence and answer only with the word OK. " + ($promptUnit * 180)

$body = @{
    model = "bonsai-2-27b-local"
    messages = @(
        @{
            role = "user"
            content = $prompt
        }
    )
    max_tokens = 32
    temperature = 0
    top_p = 1
    seed = 424242
    stream = $false
}

function Invoke-Measurement([string]$Label, [bool]$Include) {
    $response = Invoke-RestMethod -Method Post -Uri "$apiRoot/chat/completions" -Headers $headers -Body ($body | ConvertTo-Json -Depth 20)
    $prefill = Get-BonsaiJson "/debug/prefill"
    $answer = [string]$response.choices[0].message.content
    $answerBytes = [System.Text.Encoding]::UTF8.GetBytes($answer)
    $answerHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($answerBytes)).ToLowerInvariant()

    $record = [ordered]@{
        label = $Label
        included = $Include
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
    return [pscustomobject]$record
}

$all = @()
$all += Invoke-Measurement "warmup" $false
1..3 | ForEach-Object {
    $all += Invoke-Measurement "measure_$_" $true
}
$all | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $OutDir "measurements.json")

$included = @($all | Where-Object { $_.included })
$promptTokenSet = @($included.prompt_tokens | Sort-Object -Unique)
$answerHashSet = @($included.answer_sha256 | Sort-Object -Unique)

if ($promptTokenSet.Count -ne 1) {
    throw "Prompt token count changed within arm: $($promptTokenSet -join ', ')"
}
if ($answerHashSet.Count -ne 1) {
    throw "Deterministic answer changed within arm: $($answerHashSet -join ', ')"
}

$telemetryAfter = Get-BonsaiJson "/debug/telemetry"
$launchAfter = Get-BonsaiJson "/debug/phase2c/launch"
Save-Json $telemetryAfter "telemetry-after.json"
Save-Json $launchAfter "launch-after.json"

$summary = [ordered]@{
    captured_at = (Get-Date).ToString("o")
    base_url = "$apiRoot"
    build_id = $build.build_id
    phase = $launch.phase
    arm = $Arm
    process_launch_id = $launch.process_launch_id
    backend_latched_arm = $launch.backend_latched_arm
    backend_has_tensor = [bool]$launch.backend_has_tensor
    backend_evidence_valid = [bool]$launch.backend_evidence_valid
    ggml_metal_tensor_disable = $launch.ggml_metal_tensor_disable
    prompt_tokens = [int]$promptTokenSet[0]
    answer_sha256 = [string]$answerHashSet[0]
    samples = $included.Count
    avg_prefill_ms = [double](($included.prefill_ms | Measure-Object -Average).Average)
    avg_decode_to_first_token_ms = [double](($included.decode_to_first_token_ms | Measure-Object -Average).Average)
    avg_ttft_ms = [double](($included.ttft_ms | Measure-Object -Average).Average)
    avg_tokens_per_second = [double](($included.tokens_per_second | Measure-Object -Average).Average)
    next_launch_arm_requested = $NextArm
}
Save-Json $summary "summary.json"

if (-not [string]::IsNullOrWhiteSpace($NextArm)) {
    $scheduled = Post-BonsaiJson "/debug/phase2c/next-launch" @{ arm = $NextArm }
    Save-Json $scheduled "next-launch.json"
    if ($scheduled.next_launch_arm -ne $NextArm) {
        throw "Failed to schedule next launch arm $NextArm."
    }
    if ($NextArm -ne $Arm -and $scheduled.restart_required -ne $true) {
        throw "Restart requirement was not asserted after scheduling a different arm."
    }
}

$zipPath = "$OutDir.zip"
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath

Write-Host "Phase 2C-1 fresh-backend arm: PASS"
Write-Host "Arm: $Arm"
Write-Host "Backend has_tensor: $($launch.backend_has_tensor)"
Write-Host ("Avg prefill ms: {0:N3}" -f $summary.avg_prefill_ms)
Write-Host ("Avg TTFT ms: {0:N3}" -f $summary.avg_ttft_ms)
Write-Host ("Avg tok/s: {0:N3}" -f $summary.avg_tokens_per_second)
if (-not [string]::IsNullOrWhiteSpace($NextArm)) {
    Write-Host "Next launch arm: $NextArm (restart required if different)"
}
Write-Host "Evidence: $zipPath"
