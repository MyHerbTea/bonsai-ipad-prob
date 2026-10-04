param(
    [Parameter(Mandatory=$true)]
    [string]$Image1,

    [Parameter(Mandatory=$true)]
    [string]$Image2,

    [Parameter(Mandatory=$true)]
    [string]$Image3,

    [Parameter(Mandatory=$true)]
    [string]$ApiKey,

    [string]$BaseUrl = "http://192.168.0.103:8080/v1",
    [string]$Model = "bonsai-2-27b-local"
)

$ErrorActionPreference = "Stop"

$Headers = @{
    Authorization  = "Bearer $ApiKey"
    "Content-Type" = "application/json; charset=utf-8"
}

function Convert-ImageToDataUrl {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Image not found: $Path"
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        ".png"  { $mime = "image/png" }
        ".jpg"  { $mime = "image/jpeg" }
        ".jpeg" { $mime = "image/jpeg" }
        default { throw "Only PNG/JPG/JPEG are supported: $Path" }
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $b64 = [Convert]::ToBase64String($bytes)
    return "data:$mime;base64,$b64"
}

Write-Host ""
Write-Host "============================================================"
Write-Host "BONSAI RC1.25.0 BUILD 57 - THREE IMAGE API PROBE"
Write-Host "============================================================"

$Data1 = Convert-ImageToDataUrl $Image1
$Data2 = Convert-ImageToDataUrl $Image2
$Data3 = Convert-ImageToDataUrl $Image3

$Prompt = @"
Compare the three images carefully. First describe each image separately as Image 1, Image 2, and Image 3. Then state the most important similarities and differences. Do not merge the three images into one scene.
"@

$BodyObject = @{
    model = $Model
    messages = @(
        @{
            role = "user"
            content = @(
                @{ type = "text"; text = $Prompt },
                @{ type = "image_url"; image_url = @{ url = $Data1 } },
                @{ type = "image_url"; image_url = @{ url = $Data2 } },
                @{ type = "image_url"; image_url = @{ url = $Data3 } }
            )
        }
    )
    max_completion_tokens = 192
    reasoning_effort = "none"
    stream = $false
}

$Body = $BodyObject | ConvertTo-Json -Depth 20 -Compress

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$Response = Invoke-RestMethod `
    -Uri "$BaseUrl/chat/completions" `
    -Method Post `
    -Headers $Headers `
    -Body $Body `
    -TimeoutSec 300
$sw.Stop()

$Result = [PSCustomObject]@{
    test = "RC1.25.0 Build 57 Three Image API Probe"
    elapsed_s = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
    prompt_tokens = $Response.usage.prompt_tokens
    completion_tokens = $Response.usage.completion_tokens
    finish_reason = $Response.choices[0].finish_reason
    response = $Response.choices[0].message.content
    image1 = $Image1
    image2 = $Image2
    image3 = $Image3
}

Write-Host ""
Write-Host "Elapsed: $($Result.elapsed_s) s"
Write-Host "Prompt tokens: $($Result.prompt_tokens)"
Write-Host "Completion tokens: $($Result.completion_tokens)"
Write-Host "Finish reason: $($Result.finish_reason)"
Write-Host ""
Write-Host "MODEL RESPONSE"
Write-Host "------------------------------------------------------------"
Write-Host $Result.response
Write-Host "------------------------------------------------------------"

$Output = "D:\\apple\\BONSAI-B57-THREE-IMAGE-PROBE.json"
$Result | ConvertTo-Json -Depth 20 | Set-Content -Path $Output -Encoding UTF8

Write-Host ""
Write-Host "Saved: $Output"
Write-Host "Now copy the full Bonsai diagnostic snapshot."
