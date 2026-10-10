#requires -Version 7.0
<#
Build99 two-turn real-device speed experiment.
API key from BONSAI_API_KEY or secure prompt; never written to disk.
No remote setting changes. No extra packages required.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BaseUrl,
    [string]$Model = 'bonsai-2-27b-local',
    [string]$OutputRoot = '.\build99-prefix-results'
)
$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')
if ($BaseUrl -notmatch '^https?://[^/]+/v1$') { throw 'BaseUrl must end in /v1' }
$root = $BaseUrl.Substring(0, $BaseUrl.Length - 3)
$key = $env:BONSAI_API_KEY
if ([string]::IsNullOrWhiteSpace($key)) {
    $secure = Read-Host 'iPad API key (not saved)' -AsSecureString
    $key = [System.Net.NetworkCredential]::new('', $secure).Password
}
if ([string]::IsNullOrWhiteSpace($key)) { throw 'Missing API key' }
$headers = @{ Authorization = "Bearer $key" }
$initial = Invoke-RestMethod -Uri "$root/debug/prefill" -Headers $headers -TimeoutSec 30
$arm = [string]$initial.build99_append_only.active_arm
if ($arm -notin @('OFF','APPEND')) { throw 'Build99 diagnostics missing; install correct IPA' }
if ([int]$initial.build79_requested_context -ne 32768) {
    throw ('Expected 32768 context, observed {0}' -f $initial.build79_requested_context)
}
$out = Join-Path $OutputRoot ('{0}-{1}' -f $arm,(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Path $out -Force | Out-Null
$initial | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $out 'initial.json') -Encoding utf8
$sys = 'Give concise accurate answers. Never fabricate unseen inputs.'
$u1 = 'Alder, Birch, Cedar, Delta, Echo, and Foxtrot form a sequential deployment manifest. Each later stage depends on the previous stage. Summarize the complete order and the invariant that prohibits fabrication of missing bytes.'
$u2 = 'Using that same deployment manifest and your previous answer, explain in two sentences why a missing stage cannot be reconstructed without original evidence.'

function Invoke-Turn {
    param([object[]]$Messages,[string]$Case)
    $body = @{model=$Model;messages=$Messages;temperature=0;max_tokens=96;stream=$false} | ConvertTo-Json -Depth 20
    $params = @{ Uri="$BaseUrl/chat/completions";Method='Post';Headers=$headers;ContentType='application/json; charset=utf-8';Body=[Text.Encoding]::UTF8.GetBytes($body);TimeoutSec=900 }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $answer = Invoke-RestMethod @params
    $clock.Stop()
    $after = Invoke-RestMethod -Uri "$root/debug/prefill" -Headers $headers -TimeoutSec 30
    $text = [string]$answer.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($text)) { throw ('Empty response for {0}' -f $Case) }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))
    $result = [ordered]@{
        case=$Case;arm=$arm;wall_ms=[math]::Round($clock.Elapsed.TotalMilliseconds,2)
        prompt_tokens=$after.last.prompt_tokens
        completion_tokens=$after.last.completion_tokens
        prefill_ms=$after.last.prefill_ms
        decode_tps=$after.last.tokens_per_second
        text_sha256=$hash
        kv_reuse=$after.text_kv_reuse
        resident_tokens=$after.build99_append_only.resident_token_count
        finish_reason=$answer.choices[0].finish_reason
    }
    $result | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $out "$Case.json") -Encoding utf8
    Write-Host ('[{0}] prefill={1}ms reused={2} reason={3}' -f $Case,$result.prefill_ms,$result.kv_reuse.reused_tokens,$result.kv_reuse.reason)
    return @{ text=$text; data=$result }
}
try {
    $first = Invoke-Turn -Case 'first' -Messages @(
        @{role='system';content=$sys},
        @{role='user';content=$u1}
    )
    $followup = Invoke-Turn -Case 'followup' -Messages @(
        @{role='system';content=$sys},
        @{role='user';content=$u1},
        @{role='assistant';content=$first.text},
        @{role='user';content=$u2}
    )
    $matched = $arm -eq 'APPEND' -and $followup.data.kv_reuse.hit -eq $true -and $followup.data.kv_reuse.reason -eq 'append_only_exact_extension'
    $status = if ($arm -eq 'APPEND' -and -not $matched) {'NO_EXACT_PREFIX_MATCH'} else {'EVIDENCE_CAPTURED_NOT_CERTIFIED'}
    $summary = [ordered]@{schema='build99-prefix-probe-v1';arm=$arm;status=$status;matched=$matched;first=$first.data;followup=$followup.data}
    $summary | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $out 'summary.json') -Encoding utf8
    Write-Host ('Result: {0}. Evidence: {1}' -f $status,$out)
} catch {
    @{status='ERROR';message=$_.Exception.Message} | ConvertTo-Json | Set-Content (Join-Path $out 'error.json') -Encoding utf8
    throw
}
