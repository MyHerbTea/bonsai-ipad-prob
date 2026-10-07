param(
    [string]$BaseUrl = "http://192.168.0.102:8080",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Set BONSAI_API_KEY or pass -ApiKey." }

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Get-Location) "re_output/rc126-phase2h0-practical-2048-t$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$root = $BaseUrl.TrimEnd("/")
$headers = @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }

function Save-Json($Value, [string]$Name) {
    $Value | ConvertTo-Json -Depth 40 | Set-Content -Encoding utf8 (Join-Path $OutDir $Name)
}
function Get-Json([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers
}
function RepeatedPrompt([int]$Repeat, [string]$Codeword) {
    $payload = ("alpha beta gamma delta epsilon zeta eta theta " * $Repeat)
    "Read the payload below. Do not summarize it. At the end answer exactly $Codeword and nothing else.`n\n$payload"
}
function Invoke-ChatCase([string]$Name, [object[]]$Messages, [int]$MaxTokens, [string]$ExpectedContains = "") {
    Write-Host ""
    Write-Host "Running $Name ..."
    $before = Get-Json "/debug/telemetry"
    $bodyObj = @{
        model = "bonsai-2-27b-local"
        messages = $Messages
        max_tokens = $MaxTokens
        temperature = 0
        top_p = 1
        seed = 424242
        stream = $false
    }
    $body = $bodyObj | ConvertTo-Json -Depth 40
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$root/v1/chat/completions" -Headers $headers -Body $body -TimeoutSec 900
    $sw.Stop()
    $prefill = Get-Json "/debug/prefill"
    $after = Get-Json "/debug/telemetry"

    Save-Json $bodyObj "$Name-request.json"
    Save-Json $response "$Name-response.json"
    Save-Json $prefill "$Name-prefill.json"
    Save-Json $before "$Name-telemetry-before.json"
    Save-Json $after "$Name-telemetry-after.json"

    $m = $prefill.last
    $text = [string]$response.choices[0].message.content
    $ok = $true
    if (-not [string]::IsNullOrWhiteSpace($ExpectedContains)) { $ok = $text.Contains($ExpectedContains) }

    $row = [PSCustomObject]@{
        name=$Name; passed=$ok; wall_ms=[math]::Round($sw.Elapsed.TotalMilliseconds,3)
        prompt_tokens=[int]$m.prompt_tokens; completion_tokens=[int]$m.completion_tokens
        finish_reason=[string]$response.choices[0].finish_reason
        prefill_ms=[math]::Round([double]$m.prefill_ms,3)
        decode_to_first_token_ms=[math]::Round([double]$m.decode_to_first_token_ms,3)
        ttft_ms=[math]::Round([double]$m.ttft_ms,3)
        tokens_per_second=[math]::Round([double]$m.tokens_per_second,3)
        thermal_before=[string]$before.thermal_state; thermal_after=[string]$after.thermal_state
        available_before=[int64]$before.available_bytes; available_after=[int64]$after.available_bytes
        resident_delta=[int64]$after.resident_bytes-[int64]$before.resident_bytes
        footprint_delta=[int64]$after.phys_footprint_bytes-[int64]$before.phys_footprint_bytes
        metal_delta=[int64]$after.metal_allocated_bytes-[int64]$before.metal_allocated_bytes
    }
    Write-Host ("{0}: prompt={1} completion={2} prefill={3:N1}ms TTFT={4:N1}ms decode={5:N3}tok/s PASS={6}" -f $row.name,$row.prompt_tokens,$row.completion_tokens,$row.prefill_ms,$row.ttft_ms,$row.tokens_per_second,$row.passed)
    return $row
}

$build = Get-Json "/debug/build"
$health = Get-Json "/health"
$shape = Get-Json "/debug/phase2f/launch"
Save-Json $build "00-build.json"; Save-Json $health "00-health.json"; Save-Json $shape "00-shape.json"

if ($build.build_id -ne "rc1.26-build75-api-cold-start-guard") { throw "Expected Build 75, got $($build.build_id)" }
if ([int]$health.context_window -ne 2048) { throw "Expected context_window=2048, got $($health.context_window)" }
if ([int]$shape.active_batch -ne 32 -or [int]$shape.active_ubatch -ne 32) { throw "Expected 32/32 runtime shape." }

$rows = @()
$rows += Invoke-ChatCase "01-short" @(@{role="user";content="Answer exactly SHORT_OK and nothing else."}) 16 "SHORT_OK"

$seq = "Continue the following integer sequence in order, separated by single spaces. Output numbers only. Continue until the generation limit forcibly stops you.`n\n1 2 3 4 5 6 7 8 9 10"
$rows += Invoke-ChatCase "02-sustained-128" @(@{role="user";content=$seq}) 128

$rows += Invoke-ChatCase "03-context-medium" @(@{role="user";content=(RepeatedPrompt 64 "MEDIUM_OK")}) 16 "MEDIUM_OK"
$rows += Invoke-ChatCase "04-context-1k" @(@{role="user";content=(RepeatedPrompt 115 "CTX1K_OK")}) 32 "CTX1K_OK"
$rows += Invoke-ChatCase "05-context-1p5k" @(@{role="user";content=(RepeatedPrompt 179 "CTX15K_OK")}) 48 "CTX15K_OK"
$rows += Invoke-ChatCase "06-context-near-limit" @(@{role="user";content=(RepeatedPrompt 205 "NEAR_LIMIT_OK")}) 64 "NEAR_LIMIT_OK"

$multi = @(
    @{role="system";content="Follow the conversation and answer the final question exactly."},
    @{role="user";content="Remember this codeword: ORCHID-75-PRACTICAL."},
    @{role="assistant";content="I will remember it."},
    @{role="user";content="What is 2+2?"},
    @{role="assistant";content="4"},
    @{role="user";content="Now output only the codeword I gave you earlier."}
)
$rows += Invoke-ChatCase "07-multi-turn-history" $multi 32 "ORCHID-75-PRACTICAL"

Write-Host ""
Write-Host "Running 08-streaming-sse ..."
$streamObj = @{
    model="bonsai-2-27b-local"; messages=@(@{role="user";content="Count from 1 to 20 using spaces only."})
    max_tokens=64; temperature=0; top_p=1; seed=424242; stream=$true
    stream_options=@{include_usage=$true}
}
$streamBody = $streamObj | ConvertTo-Json -Depth 20 -Compress
$streamText = & curl.exe -sS -N -X POST "$root/v1/chat/completions" -H "Authorization: Bearer $ApiKey" -H "Content-Type: application/json" --data-binary $streamBody
$streamJoined = $streamText -join "`n"
$streamJoined | Set-Content -Encoding utf8 (Join-Path $OutDir "08-streaming-sse.txt")
$streamPass = $streamJoined.Contains("data:") -and $streamJoined.Contains("[DONE]")
$rows += [PSCustomObject]@{name="08-streaming-sse";passed=$streamPass;wall_ms=0;prompt_tokens=0;completion_tokens=0;finish_reason="stream";prefill_ms=0;decode_to_first_token_ms=0;ttft_ms=0;tokens_per_second=0;thermal_before="";thermal_after="";available_before=0;available_after=0;resident_delta=0;footprint_delta=0;metal_delta=0}
Write-Host "08-streaming-sse PASS=$streamPass"

Write-Host ""
Write-Host "Running 09-context-overflow-negative ..."
$overflowObj = @{
    model="bonsai-2-27b-local"; messages=@(@{role="user";content=(RepeatedPrompt 320 "SHOULD_NOT_RUN")})
    max_tokens=128; temperature=0; top_p=1; seed=424242; stream=$false
}
$overflowBody = $overflowObj | ConvertTo-Json -Depth 20
$status=0; $bodyText=""
try {
    $r=Invoke-WebRequest -Method Post -Uri "$root/v1/chat/completions" -Headers $headers -Body $overflowBody -TimeoutSec 900
    $status=[int]$r.StatusCode; $bodyText=[string]$r.Content
} catch {
    if ($null -ne $_.Exception.Response) { $status=[int]$_.Exception.Response.StatusCode }
    if ($_.ErrorDetails.Message) { $bodyText=[string]$_.ErrorDetails.Message } else { $bodyText=[string]$_ }
}
Save-Json ([ordered]@{status=$status;body=$bodyText}) "09-context-overflow-negative.json"
$overflowPass = ($status -eq 400) -and ($bodyText -match "context_length_exceeded|context|Context")
$rows += [PSCustomObject]@{name="09-context-overflow-negative";passed=$overflowPass;wall_ms=0;prompt_tokens=0;completion_tokens=0;finish_reason="expected_rejection";prefill_ms=0;decode_to_first_token_ms=0;ttft_ms=0;tokens_per_second=0;thermal_before="";thermal_after="";available_before=0;available_after=0;resident_delta=0;footprint_delta=0;metal_delta=0}
Write-Host "09-context-overflow-negative status=$status PASS=$overflowPass"

Save-Json (Get-Json "/health") "10-final-health.json"
Save-Json (Get-Json "/debug/telemetry") "10-final-telemetry.json"

$rows | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $OutDir "summary.csv")
$failed=@($rows | Where-Object { -not $_.passed })
Save-Json ([ordered]@{
    phase="RC1.26_PHASE2H0_PRACTICAL_2048"; build=75; context_window=2048
    batch=32; ubatch=32; total_cases=$rows.Count; failed_cases=$failed.Count
    failed_names=@($failed | ForEach-Object {$_.name}); overall_pass=($failed.Count -eq 0)
}) "result.json"

$zip="$OutDir.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zip
Write-Host ""
Write-Host "PHASE 2H0 PRACTICAL 2048 COMPLETE"
Write-Host "Cases: $($rows.Count)"
Write-Host "Failures: $($failed.Count)"
Write-Host "Overall PASS: $($failed.Count -eq 0)"
Write-Host "Evidence: $zip"
