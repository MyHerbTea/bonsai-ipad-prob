param(
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [string]$BaseUrl = "http://192.168.0.103:8080/v1",
    [string]$Model = "bonsai-2-27b-local",
    [string]$ImagePath = "D:\apple\vision_test_01_people_landscape.png",
    [string]$TextPrompt = "Reply with one concise sentence describing why the sky appears blue.",
    [string]$VisionPrompt = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Keep this file ASCII-only so Windows PowerShell 5.1 never depends on
# the script file's source encoding for the default Chinese prompt.
$DefaultVisionPromptBase64 = "6K+35o+P6L+w6L+Z5byg5Zu+54mH5Lit55qE5Lq654mp44CB5Yqo54mp5ZKM6IOM5pmv44CC"
if ([string]::IsNullOrWhiteSpace($VisionPrompt)) {
    $VisionPrompt = [System.Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($DefaultVisionPromptBase64)
    )
}

$endpoint = $BaseUrl.TrimEnd("/") + "/chat/completions"
$budgets = @(32, 64, 128)

function Invoke-Utf8JsonPost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [byte[]]$BodyBytes
    )

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = "POST"
    $request.ContentType = "application/json; charset=utf-8"
    $request.Accept = "application/json"
    $request.Headers["Authorization"] = "Bearer $ApiKey"
    $request.Timeout = 300000
    $request.ReadWriteTimeout = 300000
    $request.ContentLength = $BodyBytes.Length

    $requestStream = $request.GetRequestStream()
    try {
        $requestStream.Write($BodyBytes, 0, $BodyBytes.Length)
    }
    finally {
        $requestStream.Dispose()
    }

    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        try {
            $responseStream = $response.GetResponseStream()
            $reader = [System.IO.StreamReader]::new(
                $responseStream,
                [System.Text.Encoding]::UTF8,
                $true
            )
            try {
                $responseJson = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
                $responseStream.Dispose()
            }

            return $responseJson | ConvertFrom-Json
        }
        finally {
            $response.Dispose()
        }
    }
    catch [System.Net.WebException] {
        $errorResponse = $_.Exception.Response
        if ($null -ne $errorResponse) {
            try {
                $errorStream = $errorResponse.GetResponseStream()
                $errorReader = [System.IO.StreamReader]::new(
                    $errorStream,
                    [System.Text.Encoding]::UTF8,
                    $true
                )
                try {
                    $errorText = $errorReader.ReadToEnd()
                }
                finally {
                    $errorReader.Dispose()
                    $errorStream.Dispose()
                }

                throw "HTTP request failed: $errorText"
            }
            finally {
                $errorResponse.Dispose()
            }
        }

        throw
    }
}

function Invoke-BonsaiProbe {
    param(
        [string]$Label,
        [int]$Budget,
        [object[]]$Messages
    )

    $bodyJson = @{
        model = $Model
        messages = $Messages
        max_completion_tokens = $Budget
        stream = $false
        reasoning_effort = "none"
    } | ConvertTo-Json -Depth 12 -Compress

    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    $bodyRoundTrip = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
    if ($bodyRoundTrip -ne $bodyJson) {
        throw "UTF-8 request round-trip validation failed."
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-Utf8JsonPost -Uri $endpoint -BodyBytes $bodyBytes
    $sw.Stop()

    $choice = $response.choices[0]
    $usage = $response.usage
    $content = [string]$choice.message.content
    $compact = ($content -replace "\r?\n", " ").Trim()

    [pscustomobject]@{
        Label = $Label
        Requested = $Budget
        HTTP = 200
        CompletionTokens = [int]$usage.completion_tokens
        FinishReason = [string]$choice.finish_reason
        E2E_MS = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        Content = $compact
    }
}

Write-Host "RC1.23.4 BUILD 46 GENERATION TELEMETRY"
Write-Host "PowerShell 5.1 UTF-8 request/response mode: explicit"
Write-Host "Runtime Profile should remain Full / Accelerated."
Write-Host ""

$results = @()

foreach ($budget in $budgets) {
    $messages = @(
        @{
            role = "user"
            content = $TextPrompt
        }
    )
    $result = Invoke-BonsaiProbe -Label "TEXT_$budget" -Budget $budget -Messages $messages
    $results += $result
    Write-Host ("{0} requested={1} completion={2} finish={3} e2e_ms={4}" -f $result.Label, $result.Requested, $result.CompletionTokens, $result.FinishReason, $result.E2E_MS)
    Write-Host ("CONTENT: " + $result.Content)
    Write-Host ""
}

if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "Image not found: $ImagePath"
}

$imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
$imageBase64 = [Convert]::ToBase64String($imageBytes)
$imageDataUrl = "data:image/png;base64,$imageBase64"

foreach ($budget in $budgets) {
    $messages = @(
        @{
            role = "user"
            content = @(
                @{
                    type = "image_url"
                    image_url = @{
                        url = $imageDataUrl
                    }
                },
                @{
                    type = "text"
                    text = $VisionPrompt
                }
            )
        }
    )
    $result = Invoke-BonsaiProbe -Label "VISION_$budget" -Budget $budget -Messages $messages
    $results += $result
    Write-Host ("{0} requested={1} completion={2} finish={3} e2e_ms={4}" -f $result.Label, $result.Requested, $result.CompletionTokens, $result.FinishReason, $result.E2E_MS)
    Write-Host ("CONTENT: " + $result.Content)
    Write-Host ""
}

Write-Host "=== SUMMARY ==="
$results | Format-Table Label, Requested, CompletionTokens, FinishReason, E2E_MS -AutoSize
Write-Host ""
Write-Host "Copy the full iPad Diagnostic Snapshot now."
Write-Host "The snapshot history contains effective_max_tokens and termination_reason."
