param(
    [Parameter(Mandatory=$true)][string]$ApiKey,
    [Parameter(Mandatory=$true)][ValidateSet("safe","flash","accelerated")][string]$Profile,
    [string]$BaseUrl = "http://192.168.0.103:8080/v1",
    [string]$ImagePath = "D:\\apple\\vision_test_01_people_landscape.png",
    [int]$Hits = 6,
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

Write-Host ("RC1.23.3 BUILD 44 PROFILE={0}" -f $Profile)
Write-Host "Confirm the same profile is selected on iPad BEFORE API start."
$rows = @()
for ($i=0; $i -le $Hits; $i++) {
  $label = if ($i -eq 0) { "SEED" } else { "HIT_$i" }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $resp = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/chat/completions" -Method Post -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body -TimeoutSec 180
  $sw.Stop()
  $ms = $sw.Elapsed.TotalMilliseconds
  Write-Host ("{0} HTTP={1} E2E_MS={2:N1}" -f $label,[int]$resp.StatusCode,$ms)
  if ($i -gt 0) { $rows += $ms }
  if ($i -lt $Hits) { Start-Sleep -Seconds $DelaySeconds }
}
if ($rows.Count -gt 0) {
  $s = $rows | Measure-Object -Average -Minimum -Maximum
  Write-Host ("PROFILE={0} AVG_HIT_MS={1:N1} MIN={2:N1} MAX={3:N1}" -f $Profile,$s.Average,$s.Minimum,$s.Maximum)
}
Write-Host "Copy the full Diagnostic Snapshot before changing profile."
