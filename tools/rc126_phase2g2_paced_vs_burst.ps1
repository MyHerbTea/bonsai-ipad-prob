param(
    [string]$BaseUrl = "http://192.168.0.102:8080",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [int]$ResetIdleSeconds = 60,
    [int]$PacedGapSeconds = 15,
    [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "Set BONSAI_API_KEY or pass -ApiKey."
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Get-Location) "re_output/rc126-phase2g2-paced-ab-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$root = $BaseUrl.TrimEnd("/")
$headers = @{
    Authorization = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}

$build = Invoke-RestMethod -Method Get -Uri "$root/debug/build" -Headers $headers
$shape = Invoke-RestMethod -Method Get -Uri "$root/debug/phase2f/launch" -Headers $headers

if ($build.build_id -ne "rc1.26-build75-api-cold-start-guard") {
    throw "Expected Build 75, got $($build.build_id)"
}
if ([int]$shape.active_batch -ne 32 -or [int]$shape.active_ubatch -ne 32) {
    throw "Expected 32/32 runtime shape, got $($shape.active_batch)/$($shape.active_ubatch)"
}

$prompt = @"
Continue the following integer sequence in order, separated by single spaces.
Output numbers only. Do not explain, summarize, add punctuation, or stop voluntarily.
Continue until the generation limit forcibly stops you.

1 2 3 4 5 6 7 8 9 10
"@

$body = @{
    model = "bonsai-2-27b-local"
    messages = @(@{role="user"; content=$prompt})
    max_tokens = 128
    temperature = 0
    top_p = 1
    seed = 424242
    stream = $false
} | ConvertTo-Json -Depth 10

function Save-Json($Value,[string]$Name) {
    $Value | ConvertTo-Json -Depth 30 |
        Set-Content -Encoding utf8 (Join-Path $OutDir $Name)
}

function Invoke-Sample([string]$Name,[string]$Mode,[int]$Ordinal) {
    $before = Invoke-RestMethod -Method Get -Uri "$root/debug/telemetry" -Headers $headers
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $response=Invoke-RestMethod -Method Post -Uri "$root/v1/chat/completions" -Headers $headers -Body $body -TimeoutSec 600
    $sw.Stop()
    $prefill=Invoke-RestMethod -Method Get -Uri "$root/debug/prefill" -Headers $headers
    $after=Invoke-RestMethod -Method Get -Uri "$root/debug/telemetry" -Headers $headers

    Save-Json $response "$Name-response.json"
    Save-Json $prefill "$Name-prefill.json"
    Save-Json $before "$Name-telemetry-before.json"
    Save-Json $after "$Name-telemetry-after.json"

    $m=$prefill.last
    $row=[PSCustomObject]@{
        mode=$Mode
        ordinal=$Ordinal
        name=$Name
        wall_ms=[math]::Round($sw.Elapsed.TotalMilliseconds,3)
        prompt_tokens=[int]$m.prompt_tokens
        completion_tokens=[int]$m.completion_tokens
        finish_reason=[string]$response.choices[0].finish_reason
        prefill_ms=[math]::Round([double]$m.prefill_ms,3)
        decode_to_first_token_ms=[math]::Round([double]$m.decode_to_first_token_ms,3)
        ttft_ms=[math]::Round([double]$m.ttft_ms,3)
        tokens_per_second=[math]::Round([double]$m.tokens_per_second,3)
        thermal_before=[string]$before.thermal_state
        thermal_after=[string]$after.thermal_state
        resident_delta=[int64]$after.resident_bytes-[int64]$before.resident_bytes
        footprint_delta=[int64]$after.phys_footprint_bytes-[int64]$before.phys_footprint_bytes
        metal_delta=[int64]$after.metal_allocated_bytes-[int64]$before.metal_allocated_bytes
    }
    Write-Host ("{0}: {1:N3} tok/s | first={2:N3} ms | prefill={3:N3} ms" -f $Name,$row.tokens_per_second,$row.decode_to_first_token_ms,$row.prefill_ms)
    return $row
}

$rows=@()

Write-Host "PHASE A: 5 back-to-back requests"
1..5 | ForEach-Object {
    $rows += Invoke-Sample "burst_$($_)" "burst" $_
}

Write-Host ""
Write-Host "Reset idle: $ResetIdleSeconds seconds"
Start-Sleep -Seconds $ResetIdleSeconds

Write-Host ""
Write-Host "PHASE B: 5 paced requests with $PacedGapSeconds-second gaps"
1..5 | ForEach-Object {
    if ($_ -gt 1) {
        Write-Host "Paced gap: $PacedGapSeconds seconds"
        Start-Sleep -Seconds $PacedGapSeconds
    }
    $rows += Invoke-Sample "paced_$($_)" "paced" $_
}

$rows | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $OutDir "summary.csv")

$burst=@($rows | Where-Object mode -eq "burst")
$paced=@($rows | Where-Object mode -eq "paced")

function SlopePct($set) {
    if ($set.Count -lt 2 -or $set[0].tokens_per_second -le 0) { return 0 }
    return (($set[-1].tokens_per_second / $set[0].tokens_per_second)-1)*100
}

$burstAvg=($burst | Measure-Object tokens_per_second -Average).Average
$pacedAvg=($paced | Measure-Object tokens_per_second -Average).Average
$burstSlope=SlopePct $burst
$pacedSlope=SlopePct $paced

$result=[ordered]@{
    phase="RC1.26_PHASE2G2_PACED_VS_BURST"
    build=75
    reset_idle_seconds=$ResetIdleSeconds
    paced_gap_seconds=$PacedGapSeconds
    burst_avg_tokens_per_second=[math]::Round($burstAvg,3)
    paced_avg_tokens_per_second=[math]::Round($pacedAvg,3)
    burst_first_to_last_percent=[math]::Round($burstSlope,3)
    paced_first_to_last_percent=[math]::Round($pacedSlope,3)
    paced_vs_burst_avg_percent=[math]::Round((($pacedAvg/$burstAvg)-1)*100,3)
}
Save-Json $result "result.json"
Save-Json $build "build.json"
Save-Json $shape "shape.json"

$zip="$OutDir.zip"
if(Test-Path $zip){Remove-Item -Force $zip}
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zip

Write-Host ""
Write-Host "PHASE 2G2 COMPLETE"
Write-Host ("Burst avg:  {0:N3} tok/s" -f $burstAvg)
Write-Host ("Paced avg:  {0:N3} tok/s" -f $pacedAvg)
Write-Host ("Burst slope first->last: {0:N3}%" -f $burstSlope)
Write-Host ("Paced slope first->last: {0:N3}%" -f $pacedSlope)
Write-Host ("Paced vs burst average:   {0:N3}%" -f ((($pacedAvg/$burstAvg)-1)*100))
Write-Host "Evidence: $zip"
