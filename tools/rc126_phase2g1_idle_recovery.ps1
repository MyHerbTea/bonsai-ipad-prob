param(
    [string]$BaseUrl = "http://192.168.0.102:8080",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [int]$IdleSeconds = 60,
    [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "Set BONSAI_API_KEY or pass -ApiKey."
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Get-Location) "re_output/rc126-phase2g1-idle-recovery-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$root = $BaseUrl.TrimEnd("/")
$headers = @{
    Authorization = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}

$prompt = @"
Continue the following integer sequence in order, separated by single spaces.
Output numbers only. Do not explain, summarize, add punctuation, or stop voluntarily.
Continue until the generation limit forcibly stops you.

1 2 3 4 5 6 7 8 9 10
"@

$body = @{
    model = "bonsai-2-27b-local"
    messages = @(@{ role = "user"; content = $prompt })
    max_tokens = 128
    temperature = 0
    top_p = 1
    seed = 424242
    stream = $false
} | ConvertTo-Json -Depth 10

function Save-Json($Value, [string]$Name) {
    $Value | ConvertTo-Json -Depth 30 |
        Set-Content -Encoding utf8 (Join-Path $OutDir $Name)
}

function Invoke-Sample([string]$Name) {
    Write-Host ""
    Write-Host "Running $Name ..."

    $before = Invoke-RestMethod -Method Get -Uri "$root/debug/telemetry" -Headers $headers
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$root/v1/chat/completions" -Headers $headers -Body $body -TimeoutSec 600
    $sw.Stop()
    $prefill = Invoke-RestMethod -Method Get -Uri "$root/debug/prefill" -Headers $headers
    $after = Invoke-RestMethod -Method Get -Uri "$root/debug/telemetry" -Headers $headers

    Save-Json $response "$Name-response.json"
    Save-Json $prefill "$Name-prefill.json"
    Save-Json $before "$Name-telemetry-before.json"
    Save-Json $after "$Name-telemetry-after.json"

    $m = $prefill.last
    $finish = [string]$response.choices[0].finish_reason
    $row = [PSCustomObject]@{
        name = $Name
        wall_ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 3)
        prompt_tokens = [int]$m.prompt_tokens
        completion_tokens = [int]$m.completion_tokens
        finish_reason = $finish
        prefill_ms = [math]::Round([double]$m.prefill_ms, 3)
        decode_to_first_token_ms = [math]::Round([double]$m.decode_to_first_token_ms, 3)
        ttft_ms = [math]::Round([double]$m.ttft_ms, 3)
        tokens_per_second = [math]::Round([double]$m.tokens_per_second, 3)
        thermal_before = [string]$before.thermal_state
        thermal_after = [string]$after.thermal_state
        resident_delta = [int64]$after.resident_bytes - [int64]$before.resident_bytes
        footprint_delta = [int64]$after.phys_footprint_bytes - [int64]$before.phys_footprint_bytes
        metal_delta = [int64]$after.metal_allocated_bytes - [int64]$before.metal_allocated_bytes
    }

    Write-Host (
        "{0}: {1:N3} tok/s · first={2:N3} ms · prefill={3:N3} ms · thermal={4}->{5}" -f
        $Name,
        $row.tokens_per_second,
        $row.decode_to_first_token_ms,
        $row.prefill_ms,
        $row.thermal_before,
        $row.thermal_after
    )

    return $row
}

$rows = @()

# Re-establish a degraded state with five back-to-back requests.
1..5 | ForEach-Object {
    $rows += Invoke-Sample "load_$($_)"
}

$preIdle = $rows[-1]
Write-Host ""
Write-Host "Idling for $IdleSeconds seconds without stopping API or unloading model..."
Start-Sleep -Seconds $IdleSeconds

$postIdle = Invoke-Sample "post_idle"
$rows += $postIdle

$rows | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $OutDir "summary.csv")

$recoveryPct = if ($preIdle.tokens_per_second -gt 0) {
    (($postIdle.tokens_per_second / $preIdle.tokens_per_second) - 1.0) * 100.0
} else {
    0
}

$result = [ordered]@{
    phase = "RC1.26_PHASE2G1_IDLE_RECOVERY"
    build = 75
    idle_seconds = $IdleSeconds
    pre_idle_tokens_per_second = $preIdle.tokens_per_second
    post_idle_tokens_per_second = $postIdle.tokens_per_second
    recovery_percent = [math]::Round($recoveryPct, 3)
    pre_idle_decode_to_first_token_ms = $preIdle.decode_to_first_token_ms
    post_idle_decode_to_first_token_ms = $postIdle.decode_to_first_token_ms
    pre_idle_prefill_ms = $preIdle.prefill_ms
    post_idle_prefill_ms = $postIdle.prefill_ms
    pre_idle_thermal = "$($preIdle.thermal_before)->$($preIdle.thermal_after)"
    post_idle_thermal = "$($postIdle.thermal_before)->$($postIdle.thermal_after)"
}
Save-Json $result "result.json"

$zipPath = "$OutDir.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath

Write-Host ""
Write-Host "PHASE 2G1 IDLE RECOVERY COMPLETE"
Write-Host ("Pre-idle:  {0:N3} tok/s" -f $preIdle.tokens_per_second)
Write-Host ("Post-idle: {0:N3} tok/s" -f $postIdle.tokens_per_second)
Write-Host ("Recovery:  {0:N3}%" -f $recoveryPct)
Write-Host "Evidence: $zipPath"
