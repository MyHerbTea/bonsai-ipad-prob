param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [string]$BaseUrl = "http://192.168.0.103:8080/v1",
    [string]$ImagePath = "D:\\apple\\vision_test_01_people_landscape.png",
    [int]$WarmHits = 10,
    [int]$CooldownSeconds = 45,
    [int]$RecoveryHits = 10,
    [int]$DelaySeconds = 1
)

$ErrorActionPreference = "Stop"
$Model = "bonsai-2-27b-local"
$Prompt = -join @(
    [char]0x8BF7,[char]0x63CF,[char]0x8FF0,[char]0x8FD9,
    [char]0x5F20,[char]0x56FE,[char]0x7247,[char]0x4E2D,
    [char]0x7684,[char]0x4EBA,[char]0x7269,[char]0x3001,
    [char]0x52A8,[char]0x7269,[char]0x548C,[char]0x80CC,
    [char]0x666F,[char]0x3002
)

function Invoke-Vision([string]$Label, [byte[]]$Body, [hashtable]$Headers) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/chat/completions" -Method Post -Headers $Headers -ContentType "application/json; charset=utf-8" -Body $Body -TimeoutSec 180
    $sw.Stop()
    Write-Host ("{0} HTTP={1} E2E_MS={2:N1}" -f $Label,[int]$response.StatusCode,$sw.Elapsed.TotalMilliseconds)
    return $sw.Elapsed.TotalMilliseconds
}

if (-not (Test-Path -LiteralPath $ImagePath)) { throw "Image missing: $ImagePath" }
$headers = @{ Authorization = "Bearer $ApiKey" }
$imageBytes = [IO.File]::ReadAllBytes($ImagePath)
$dataUrl = "data:image/png;base64," + [Convert]::ToBase64String($imageBytes)
$request = [ordered]@{
    model = $Model
    messages = @([ordered]@{ role = "user"; content = @(
        [ordered]@{ type = "image_url"; image_url = [ordered]@{ url = $dataUrl } },
        [ordered]@{ type = "text"; text = $Prompt }
    )})
    max_completion_tokens = 128
    stream = $false
    reasoning_effort = "none"
}
$body = [Text.Encoding]::UTF8.GetBytes(($request | ConvertTo-Json -Depth 12 -Compress))

Write-Host "RC1.23.3 BUILD 43 A2 THERMAL RECOVERY PROBE"
Write-Host "Do not click/select inside a legacy PowerShell console during the run."
Invoke-Vision "SEED_EXPECT_MISS" $body $headers | Out-Null
Start-Sleep -Seconds $DelaySeconds
for ($i=1; $i -le $WarmHits; $i++) {
    Invoke-Vision ("WARM_A_{0}/{1}" -f $i,$WarmHits) $body $headers | Out-Null
    if ($i -lt $WarmHits) { Start-Sleep -Seconds $DelaySeconds }
}
Write-Host ("CONTROLLED_COOLDOWN_SECONDS={0}" -f $CooldownSeconds)
Start-Sleep -Seconds $CooldownSeconds
Write-Host "COOLDOWN_COMPLETE"
for ($i=1; $i -le $RecoveryHits; $i++) {
    Invoke-Vision ("WARM_B_{0}/{1}" -f $i,$RecoveryHits) $body $headers | Out-Null
    if ($i -lt $RecoveryHits) { Start-Sleep -Seconds $DelaySeconds }
}
Write-Host "DONE"
Write-Host "Do not send another API request. Copy the full Diagnostic Snapshot."
Write-Host "[RC1.23.3 LONG-RUN REQUEST HISTORY]"
