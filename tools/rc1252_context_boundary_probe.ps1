param(
    [string]$BaseUrl = "http://192.168.0.103:8080/v1",
    [string]$Model = "bonsai-2-27b-local",
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,
    [ValidateSet(512, 768, 1024, 2048)]
    [int]$ExpectedContext = 512,
    [string]$OutDir = "D:\apple\re_output\rc1252-context-boundary"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Save-Json { param([string]$Path,[object]$Object) $Object | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $Path }
function Require { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Invoke-Request {
    param([string]$Name,[string]$Method,[string]$Url,[string]$BodyPath="")
    $headers = Join-Path $OutDir ($Name + ".headers.txt")
    $body = Join-Path $OutDir ($Name + ".body.txt")
    $args = @("-sS","-D",$headers,"-o",$body,"-w","%{http_code}","-X",$Method,"-H",("Authorization: Bearer " + $ApiKey),"-H","Accept: application/json")
    if ($BodyPath) { $args += @("-H","Content-Type: application/json","--data-binary",("@" + $BodyPath)) }
    $status = & curl.exe @args $Url
    return [pscustomobject]@{Status=[int]$status;Body=(Get-Content -Raw $body);Headers=$headers;BodyPath=$body}
}

$repeatMap = @{ 512=240; 768=520; 1024=760; 2048=1500 }
$repeatCount = $repeatMap[$ExpectedContext]
Write-Host "RC1.25.2 Build 61 FAST CONTEXT BOUNDARY PROBE"
Write-Host "Expected Context: $ExpectedContext"
Write-Host "Evidence: $OutDir"

# 1. Discovery must report the selected active runtime context.
$models = Invoke-Request -Name "01_models" -Method "GET" -Url ($BaseUrl + "/models")
Require ($models.Status -eq 200) "GET /models failed."
$modelInfo = (($models.Body | ConvertFrom-Json).data | Where-Object { $_.id -eq $Model } | Select-Object -First 1)
Require ($null -ne $modelInfo) "Model not found."
Require ([int]$modelInfo.context_length -eq $ExpectedContext) "Discovered context does not match selected context."
Write-Host "[PASS] discovery context_length=$ExpectedContext"

# 2. One context-scaled prompt. This is intentionally the only inference in the fast gate.
$probeText = ("context-probe " * $repeatCount) + " Reply with OK only."
$request = @{model=$Model;messages=@(@{role="user";content=$probeText});max_completion_tokens=16;temperature=0;stream=$false}
$requestPath = Join-Path $OutDir ("02_context_" + $ExpectedContext + "_request.json")
Save-Json -Path $requestPath -Object $request
$response = Invoke-Request -Name ("02_context_" + $ExpectedContext) -Method "POST" -Url ($BaseUrl + "/chat/completions") -BodyPath $requestPath
Require ($response.Status -eq 200) ("Context-scaled inference failed with HTTP " + $response.Status + ". Body: " + $response.Body)
$json = $response.Body | ConvertFrom-Json
$promptTokens = [int]$json.usage.prompt_tokens
$completionTokens = [int]$json.usage.completion_tokens
Require ($promptTokens -gt 0) "prompt_tokens was not reported."
Write-Host ("[PASS] inference prompt_tokens=" + $promptTokens + " completion_tokens=" + $completionTokens)

$summary = [ordered]@{
    schema_version = 1
    expected_context = $ExpectedContext
    discovered_context = [int]$modelInfo.context_length
    prompt_tokens = $promptTokens
    completion_tokens = $completionTokens
    result = "PASS"
    note = "Fast gate only. Run full rc1252_context_ladder_device_probe.ps1 on the selected maximum stable context."
}
$summaryPath = Join-Path $OutDir ("SUMMARY-boundary-" + $ExpectedContext + ".json")
Save-Json -Path $summaryPath -Object $summary
Write-Host "============================================================"
Write-Host ("CONTEXT " + $ExpectedContext + " FAST BOUNDARY PROBE: PASS")
Write-Host "============================================================"
Write-Host ("Summary: " + $summaryPath)
