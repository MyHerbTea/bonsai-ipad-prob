param(
    [string]$BaseUrl = "http://192.168.0.103:8080/v1",
    [string]$Model = "bonsai-2-27b-local",
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,
    [ValidateSet(512, 768, 1024, 2048)]
    [int]$ExpectedContext = 512,
    [string]$OutDir = "D:\\apple\\re_output\\rc1252-context-probe"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Write-JsonFile {
    param([string]$Path, [object]$Object)
    $Object | ConvertTo-Json -Depth 16 | Set-Content -Encoding UTF8 -Path $Path
}

function Invoke-CurlJson {
    param([string]$Name, [string]$Method, [string]$Url, [string]$BodyPath = "")
    $headersPath = Join-Path $OutDir ($Name + ".headers.txt")
    $bodyPath = Join-Path $OutDir ($Name + ".body.txt")
    $args = @("-sS", "-D", $headersPath, "-o", $bodyPath, "-w", "%{http_code}", "-X", $Method, "-H", ("Authorization: Bearer " + $ApiKey), "-H", "Accept: application/json")
    if ($BodyPath) { $args += @("-H", "Content-Type: application/json", "--data-binary", ("@" + $BodyPath)) }
    $status = & curl.exe @args $Url
    return [pscustomobject]@{ Name=$Name; Status=[int]$status; HeadersPath=$headersPath; BodyPath=$bodyPath; Body=(Get-Content -Raw -Path $bodyPath) }
}

function Require {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$results = @()
Write-Host "============================================================"
Write-Host "BONSAI RC1.25.2 BUILD 61 CONTEXT LADDER DEVICE PROBE"
Write-Host "Expected Context: $ExpectedContext"
Write-Host "Output: $OutDir"
Write-Host "============================================================"

# 1. Discovery / capability contract.
$models = Invoke-CurlJson -Name "01_models" -Method "GET" -Url ($BaseUrl + "/models")
Require ($models.Status -eq 200) "GET /models expected HTTP 200, got $($models.Status)."
$modelsJson = $models.Body | ConvertFrom-Json
$modelInfo = $modelsJson.data | Where-Object { $_.id -eq $Model } | Select-Object -First 1
Require ($null -ne $modelInfo) "Model not found in /models."
Require ([int]$modelInfo.context_length -eq $ExpectedContext) "context_length mismatch."
Require ($modelInfo.architecture.input_modalities -contains "image") "Vision modality was not advertised."
Require (-not ($modelInfo.supported_parameters -contains "tool_choice")) "Server must not advertise tool_choice."
Require (-not ($modelInfo.supported_parameters -contains "reasoning_effort")) "Server must not advertise reasoning_effort."
$results += "discovery=PASS"

# 2. Non-stream text.
$nonStreamRequest = @{ model=$Model; messages=@(@{role="system";content="Reply concisely."}, @{role="user";content="Reply exactly: BUILD61_TEXT_OK"}); max_completion_tokens=64; temperature=0; top_p=1; stream=$false }
$nonStreamPath = Join-Path $OutDir "02_text_request.json"
Write-JsonFile -Path $nonStreamPath -Object $nonStreamRequest
$textResult = Invoke-CurlJson -Name "02_text" -Method "POST" -Url ($BaseUrl + "/chat/completions") -BodyPath $nonStreamPath
Require ($textResult.Status -eq 200) "Non-stream text expected HTTP 200."
$textJson = $textResult.Body | ConvertFrom-Json
Require ($textJson.choices.Count -ge 1) "Non-stream response has no choices."
Require (-not [string]::IsNullOrWhiteSpace($textJson.choices[0].message.content)) "Non-stream assistant content is empty."
$results += "text_non_stream=PASS"

# 3. Multi-turn history.
$multiTurnRequest = @{ model=$Model; messages=@(@{role="system";content="Use conversation history."}, @{role="user";content="Remember this code: ORCHID-61."}, @{role="assistant";content="I will remember ORCHID-61."}, @{role="user";content="What code did I give you? Reply with the code only."}); max_completion_tokens=48; temperature=0; stream=$false }
$multiTurnPath = Join-Path $OutDir "03_multiturn_request.json"
Write-JsonFile -Path $multiTurnPath -Object $multiTurnRequest
$multiTurn = Invoke-CurlJson -Name "03_multiturn" -Method "POST" -Url ($BaseUrl + "/chat/completions") -BodyPath $multiTurnPath
Require ($multiTurn.Status -eq 200) "Multi-turn request expected HTTP 200."
$multiTurnJson = $multiTurn.Body | ConvertFrom-Json
$multiTurnText = [string]$multiTurnJson.choices[0].message.content
Require ($multiTurnText -match "ORCHID-61") "Multi-turn history was not reflected in the answer."
$results += "multi_turn=PASS"

# 4. tool_choice=none compatibility.
$toolNoneRequest = @{ model=$Model; messages=@(@{role="user";content="Reply exactly: TOOL_NONE_OK"}); tools=@(@{type="function";function=@{name="dummy";description="Compatibility-only dummy tool";parameters=@{type="object";properties=@{}}}}); tool_choice="none"; max_completion_tokens=48; stream=$false }
$toolNonePath = Join-Path $OutDir "04_tool_none_request.json"
Write-JsonFile -Path $toolNonePath -Object $toolNoneRequest
$toolNone = Invoke-CurlJson -Name "04_tool_none" -Method "POST" -Url ($BaseUrl + "/chat/completions") -BodyPath $toolNonePath
Require ($toolNone.Status -eq 200) "tool_choice=none compatibility expected HTTP 200."
$results += "tool_choice_none=PASS"

# 5. Actual tool execution remains unsupported.
$toolAutoRequest = @{ model=$Model; messages=@(@{role="user";content="Do not execute tools."}); tools=$toolNoneRequest.tools; tool_choice="auto"; max_completion_tokens=32; stream=$false }
$toolAutoPath = Join-Path $OutDir "05_tool_auto_request.json"
Write-JsonFile -Path $toolAutoPath -Object $toolAutoRequest
$toolAuto = Invoke-CurlJson -Name "05_tool_auto" -Method "POST" -Url ($BaseUrl + "/chat/completions") -BodyPath $toolAutoPath
Require ($toolAuto.Status -eq 400) "tool_choice=auto expected HTTP 400."
Require ($toolAuto.Body -match '"code"\s*:\s*"tools_not_supported"') "tool_choice=auto did not return tools_not_supported."
$results += "tool_execution_rejection=PASS"

# 6. Deliberate context overflow; larger than every ladder candidate.
$overflowText = ("overflow-token " * 5000)
$overflowRequest = @{ model=$Model; messages=@(@{role="user";content=$overflowText}); max_completion_tokens=128; stream=$false }
$overflowPath = Join-Path $OutDir "06_overflow_request.json"
Write-JsonFile -Path $overflowPath -Object $overflowRequest
$overflow = Invoke-CurlJson -Name "06_overflow" -Method "POST" -Url ($BaseUrl + "/chat/completions") -BodyPath $overflowPath
Require ($overflow.Status -eq 400) "Overflow request expected HTTP 400."
Require ($overflow.Body -match '"code"\s*:\s*"context_length_exceeded"') "Overflow did not return context_length_exceeded."
$results += "text_context_overflow=PASS"

# 7. Streaming SSE.
$streamRequest = @{ model=$Model; messages=@(@{role="user";content="Reply exactly: STREAM_OK"}); max_completion_tokens=48; temperature=0; stream=$true; stream_options=@{include_usage=$true} }
$streamPath = Join-Path $OutDir "07_stream_request.json"
Write-JsonFile -Path $streamPath -Object $streamRequest
$streamHeaders = Join-Path $OutDir "07_stream.headers.txt"
$streamBody = Join-Path $OutDir "07_stream.body.txt"
$streamArgs = @("-sS","-N","-D",$streamHeaders,"-o",$streamBody,"-w","%{http_code}","-X","POST","-H",("Authorization: Bearer " + $ApiKey),"-H","Content-Type: application/json","--data-binary",("@" + $streamPath),($BaseUrl + "/chat/completions"))
$streamStatus = & curl.exe @streamArgs
Require ([int]$streamStatus -eq 200) "Streaming request expected HTTP 200."
$streamRaw = Get-Content -Raw -Path $streamBody
Require ($streamRaw -match "data: \[DONE\]") "SSE stream did not contain [DONE]."
Require ($streamRaw -match '"object"\s*:\s*"chat.completion.chunk"') "SSE stream did not contain chat.completion.chunk."
$results += "streaming=PASS"

$summary = [ordered]@{ schema_version=1; expected_context=$ExpectedContext; model=$Model; base_url=$BaseUrl; result="PASS"; checks=$results; output_dir=$OutDir }
$summaryPath = Join-Path $OutDir ("SUMMARY-context-" + $ExpectedContext + ".json")
Write-JsonFile -Path $summaryPath -Object $summary

Write-Host ""
Write-Host "============================================================"
Write-Host "CONTEXT $ExpectedContext DEVICE PROBE: PASS"
Write-Host "============================================================"
$results | ForEach-Object { Write-Host $_ }
Write-Host "Summary: $summaryPath"
