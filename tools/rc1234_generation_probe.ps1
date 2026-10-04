param(
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [string]$BaseUrl = "http://192.168.0.103:8080/v1",
    [string]$Model = "bonsai-2-27b-local",
    [string]$ImagePath = "D:\\apple\\vision_test_01_people_landscape.png",
    [string]$TextPrompt = "Reply with one concise sentence describing why the sky appears blue.",
    [string]$VisionPrompt = "请描述这张图片中的人物、动物和背景。"
)

$ErrorActionPreference = "Stop"
$headers = @{
    Authorization = "Bearer $ApiKey"
    "Content-Type" = "application/json"
}
$endpoint = $BaseUrl.TrimEnd("/") + "/chat/completions"
$budgets = @(32, 64, 128)

function Invoke-BonsaiProbe {
    param(
        [string]$Label,
        [int]$Budget,
        [object[]]$Messages
    )

    $body = @{
        model = $Model
        messages = $Messages
        max_completion_tokens = $Budget
        stream = $false
        reasoning_effort = "none"
    } | ConvertTo-Json -Depth 12 -Compress

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $body
    $sw.Stop()

    $choice = $response.choices[0]
    $usage = $response.usage
    $content = [string]$choice.message.content
    $compact = ($content -replace "\\r?\\n", " ").Trim()

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
