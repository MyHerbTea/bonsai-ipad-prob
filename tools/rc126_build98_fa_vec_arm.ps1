#requires -Version 7.0
<#
.SYNOPSIS
  Build98 M5 FA-vec one-arm device evidence capture.
.DESCRIPTION
  Run once for each A0/A1/A2 after changing local iPad selection and fully
  restarting the application. Uses existing authenticated diagnostics.
  Does not change any setting, arm, model, or local file on the iPad.
.EXAMPLE
  .\rc126_build98_fa_vec_arm.ps1 -ExpectedArm A0 -BaseUrl http://192.168.0.103:8080/v1
#>
[CmdletBinding()]
param(
    [ValidateSet('A0','A1','A2')][string]$ExpectedArm = 'A0',
    [string]$BaseUrl = 'http://192.168.0.103:8080/v1',
    [string]$Model = 'bonsai-2-27b-local',
    [int]$Runs = 1,
    [string]$OutputRoot = '.\build98-fa-vec-results'
)
$ErrorActionPreference = 'Stop'
if ($Runs -lt 1 -or $Runs -gt 5) { throw "Runs must be between 1 and 5" }
$BaseUrl = $BaseUrl.TrimEnd('/')
if ($BaseUrl -notmatch '^https?://[^/]+/v1$') {
    throw 'BaseUrl must be http(s)://HOST:PORT/v1'
}
$root = $BaseUrl.Substring(0, $BaseUrl.Length - 3)
$key = $env:BONSAI_API_KEY
if ([string]::IsNullOrWhiteSpace($key)) {
    $secret = Read-Host 'iPad OpenAI API Key (not saved)' -AsSecureString
    $key = [System.Net.NetworkCredential]::new('', $secret).Password
}
if ([string]::IsNullOrWhiteSpace($key)) { throw 'API key must not be empty' }
$headers = @{ Authorization = "Bearer $key" }

$before = Invoke-RestMethod -Uri "$root/debug/runtime" -Headers $headers -TimeoutSec 30
$arm = $before.fa_vec_experiment
if ($null -eq $arm) { throw 'Build98 FA-vec diagnostics absent: check installed IPA' }
if ($arm.active_arm -ne $ExpectedArm) {
    throw "Arm mismatch: expected $ExpectedArm; active $($arm.active_arm). Fully relaunch the iPad app."
}
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$out = Join-Path $OutputRoot "$ExpectedArm-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$before | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $out 'before-runtime.json') -Encoding utf8

# A deterministic >1K-token input in most tokenizers; actual token count
# is measured and must be checked from /debug/prefill, not guessed from chars.
$lines = for ($n = 1; $n -le 64; $n++) {
    "Observation $n : The benchmark ledger stores calibration values, packet indices, checksum patterns, and timestamp ordering for an isolated GPU scheduling experiment."
}
$prompt = ($lines -join "`n") + "`nSummarize why stable resource measurement matters. Write at least 300 words, no code."
$measurements = @()
for ($i = 1; $i -le $Runs; $i++) {
    $body = @{
        model = $Model
        messages = @(@{ role = 'user'; content = $prompt })
        temperature = 0
        max_tokens = 128
        stream = $false
    } | ConvertTo-Json -Depth 12
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 900
    $timer.Stop()
    $prefill = Invoke-RestMethod -Uri "$root/debug/prefill" -Headers $headers -TimeoutSec 30
    $runtime = Invoke-RestMethod -Uri "$root/debug/runtime" -Headers $headers -TimeoutSec 30
    $perf = $prefill.last
    $trace = $runtime.fa_vec_experiment
    $row = [ordered]@{
        schema = 'bonsai-build98-fa-vec-measurement-v1'
        arm = $ExpectedArm
        run = $i
        wall_ms = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
        prompt_tokens = $perf.prompt_tokens
        completion_tokens = $perf.completion_tokens
        prefill_ms = $perf.prefill_ms
        ttft_ms = $perf.ttft_ms
        decode_tps = $perf.tokens_per_second
        finish_reason = $response.choices[0].finish_reason
        api_usage = $response.usage
        native_matched = $trace.native_matched
        native_decision = $trace.native_decision
    }
    $row | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $out "run-$i.json") -Encoding utf8
    $measurements += [PSCustomObject]$row
    Write-Host "[RUN $i] arm=$ExpectedArm tokens=$($row.prompt_tokens)/$($row.completion_tokens) decode=$($row.decode_tps) tok/s native=$($row.native_matched)"
    if (-not $trace.native_matched) {
        throw "Native 256/256 Q4_0 M5 FA-vec target not observed. Evidence saved to $out. Do NOT compare performance."
    }
    if ($trace.native_decision.arm -ne $ExpectedArm) {
        throw "Native selected arm does not match requested arm. Evidence saved to $out"
    }
    if ([int]$row.prompt_tokens -lt 1024) {
        throw "Actual prompt below 1024 KV threshold; evidence saved to $out. Do NOT compare performance."
    }
    if (($ExpectedArm -eq 'A1' -and [string]$trace.native_decision.NE -ne '2') -or
        ($ExpectedArm -eq 'A2' -and [string]$trace.native_decision.NE -ne '4')) {
        throw "Native NE mismatch; evidence saved to $out"
    }
}
$measurements | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding utf8
Write-Host "PASS evidence saved to $out"
