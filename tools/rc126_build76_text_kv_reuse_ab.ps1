param(
    [string]$BaseUrl = "http://192.168.0.102:8080",
    [string]$ApiKey = $env:BONSAI_API_KEY,
    [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Set BONSAI_API_KEY or pass -ApiKey." }
$root = $BaseUrl.TrimEnd("/")
if ([string]::IsNullOrWhiteSpace($OutDir)) { $stamp = Get-Date -Format "yyyyMMdd-HHmmss"; $OutDir = Join-Path (Get-Location) "re_output/rc126-build76-text-kv-reuse-$stamp" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$headers = @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }

function Save-Json($Value,[string]$Name) { $Value | ConvertTo-Json -Depth 50 | Set-Content -Encoding utf8 (Join-Path $OutDir $Name) }
function Get-Json([string]$Path) { Invoke-RestMethod -Method Get -Uri "$root$Path" -Headers $headers }

function Invoke-Case([string]$Name,[object[]]$Messages,[int]$MaxTokens = 16) {
    $bodyObject = @{ model="bonsai-2-27b-local"; messages=$Messages; max_tokens=$MaxTokens; temperature=0; top_p=1; seed=424242; stream=$false }
    $body = $bodyObject | ConvertTo-Json -Depth 50
    $before = Get-Json "/debug/telemetry"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$root/v1/chat/completions" -Headers $headers -Body $body -TimeoutSec 900
    $sw.Stop()
    $prefill = Get-Json "/debug/prefill"
    $after = Get-Json "/debug/telemetry"
    Save-Json $bodyObject "$Name-request.json"; Save-Json $response "$Name-response.json"; Save-Json $prefill "$Name-prefill.json"; Save-Json $before "$Name-telemetry-before.json"; Save-Json $after "$Name-telemetry-after.json"
    $m = $prefill.last; $kv = $prefill.text_kv_reuse
    $row = [PSCustomObject]@{
        name=$Name; prompt_tokens=[int]$m.prompt_tokens; completion_tokens=[int]$m.completion_tokens;
        prefill_ms=[math]::Round([double]$m.prefill_ms,3); first_ms=[math]::Round([double]$m.decode_to_first_token_ms,3); ttft_ms=[math]::Round([double]$m.ttft_ms,3);
        decode_tps=[math]::Round([double]$m.tokens_per_second,3); reuse_enabled=[bool]$kv.enabled; reuse_hit=[bool]$kv.hit;
        lcp_tokens=[int]$kv.lcp_tokens; reused_tokens=[int]$kv.reused_tokens; suffix_tokens=[int]$kv.suffix_tokens; reuse_reason=[string]$kv.reason;
        thermal_before=[string]$before.thermal_state; thermal_after=[string]$after.thermal_state; available_after=[int64]$after.available_bytes; metal_after=[int64]$after.metal_allocated_bytes;
        wall_ms=[math]::Round($sw.Elapsed.TotalMilliseconds,3); text=[string]$response.choices[0].message.content
    }
    Write-Host ("{0}: prompt={1} prefill={2:N1}ms TTFT={3:N1}ms reuse={4} reused={5} suffix={6} reason={7}" -f $row.name,$row.prompt_tokens,$row.prefill_ms,$row.ttft_ms,$row.reuse_hit,$row.reused_tokens,$row.suffix_tokens,$row.reuse_reason)
    return $row
}

$build = Get-Json "/debug/build"; $health = Get-Json "/health"; $shape = Get-Json "/debug/phase2f/launch"
Save-Json $build "00-build.json"; Save-Json $health "00-health.json"; Save-Json $shape "00-shape.json"
if ($build.build_id -ne "rc1.26-build76-text-kv-reuse-lab") { throw "Expected Build 76 Text KV lab; got $($build.build_id)" }
if ([int]$health.context_window -ne 2048) { throw "Expected 2048 context; got $($health.context_window)" }
if ([int]$shape.active_batch -ne 32 -or [int]$shape.active_ubatch -ne 32) { throw "Expected 32/32 shape." }

$payload = "alpha beta gamma delta epsilon zeta eta theta " * 120
$system = "You are a deterministic local-model certification assistant.`nThe following calibration payload must remain unchanged across requests.`nDo not quote or summarize it unless explicitly asked.`n`n$payload"
$rows = @()
$messages1 = @(@{role="system";content=$system},@{role="user";content="Answer exactly STEP1_OK and nothing else."})
$rows += Invoke-Case "01-cold-long-prefix" $messages1 16
$assistant1 = $rows[-1].text
$messages2 = @(@{role="system";content=$system},@{role="user";content="Answer exactly STEP1_OK and nothing else."},@{role="assistant";content=$assistant1},@{role="user";content="Answer exactly STEP2_OK and nothing else."})
$rows += Invoke-Case "02-reuse-long-prefix" $messages2 16
$assistant2 = $rows[-1].text
$messages3 = @(@{role="system";content=$system},@{role="user";content="Answer exactly STEP1_OK and nothing else."},@{role="assistant";content=$assistant1},@{role="user";content="Answer exactly STEP2_OK and nothing else."},@{role="assistant";content=$assistant2},@{role="user";content="Answer exactly STEP3_OK and nothing else."})
$rows += Invoke-Case "03-growing-history" $messages3 16
$messages4 = @(@{role="system";content="You are a fresh unrelated conversation."},@{role="user";content="Answer exactly ISOLATION_OK and nothing else."})
$rows += Invoke-Case "04-isolation" $messages4 16
$rows | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $OutDir "summary.csv")
$cold=$rows[0]; $reuse=$rows[1]; $growing=$rows[2]; $isolation=$rows[3]
$prefillGain = if ($cold.prefill_ms -gt 0) { (1.0 - ($reuse.prefill_ms / $cold.prefill_ms)) * 100.0 } else { 0 }
$pass = $cold.reuse_enabled -and (-not $cold.reuse_hit) -and $reuse.reuse_hit -and $reuse.reused_tokens -ge 500 -and $prefillGain -ge 50 -and $growing.reuse_hit -and (-not $isolation.reuse_hit) -and $cold.text.Contains("STEP1_OK") -and $reuse.text.Contains("STEP2_OK") -and $growing.text.Contains("STEP3_OK") -and $isolation.text.Contains("ISOLATION_OK")
$result=[ordered]@{phase="RC1.26_BUILD76_TEXT_KV_REUSE";build=76;cold_prefill_ms=$cold.prefill_ms;reuse_prefill_ms=$reuse.prefill_ms;prefill_reduction_percent=[math]::Round($prefillGain,3);reuse_hit=$reuse.reuse_hit;reused_tokens=$reuse.reused_tokens;suffix_tokens=$reuse.suffix_tokens;growing_history_hit=$growing.reuse_hit;isolation_hit=$isolation.reuse_hit;overall_pass=$pass}
Save-Json $result "result.json"
$zip="$OutDir.zip"; if(Test-Path $zip){Remove-Item -Force $zip}; Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zip
Write-Host ""; Write-Host "BUILD 76 TEXT KV REUSE COMPLETE"; Write-Host ("Cold prefill: {0:N3} ms" -f $cold.prefill_ms); Write-Host ("Reuse prefill: {0:N3} ms" -f $reuse.prefill_ms); Write-Host ("Reduction: {0:N3}%" -f $prefillGain); Write-Host ("Reused tokens: {0}" -f $reuse.reused_tokens); Write-Host ("Suffix tokens: {0}" -f $reuse.suffix_tokens); Write-Host ("Isolation hit: {0}" -f $isolation.reuse_hit); Write-Host "Overall PASS: $pass"; Write-Host "Evidence: $zip"
