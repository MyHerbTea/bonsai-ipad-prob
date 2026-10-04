param(
    [string]$Destination = "D:\\models\\flashnext-p0"
)

$ErrorActionPreference = "Stop"
$repo = "neopolita/Qwen3.8-Flash-Next-102B-A5B-Niwaki-v2.4-3bit-mlx"
$shard = "model-00008-of-00008.safetensors"
$inspector = Join-Path $PSScriptRoot "inspect_flashnext_p0_index.py"

if (-not (Get-Command hf -ErrorAction SilentlyContinue)) {
    throw "Hugging Face CLI 'hf' was not found. Install/update huggingface_hub first."
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python was not found."
}
if (-not (Test-Path $inspector)) {
    throw "Missing index inspector: $inspector"
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

Write-Host "Stage 1/2: downloading only config + index."
Write-Host "No large model shard is downloaded until the index contract passes."

& hf download $repo `
    config.json `
    model.safetensors.index.json `
    --local-dir $Destination

if ($LASTEXITCODE -ne 0) {
    throw "hf metadata download failed with exit code $LASTEXITCODE"
}

$indexPath = Join-Path $Destination "model.safetensors.index.json"
& python $inspector $indexPath --preferred-shard $shard
if ($LASTEXITCODE -ne 0) {
    throw "P0-A index gate failed. The 738 MB shard was NOT downloaded."
}

$root = [System.IO.Path]::GetPathRoot($Destination)
$driveName = $root.Substring(0, 1)
$freeBefore = (Get-PSDrive -Name $driveName).Free
Write-Host ("Free space before shard: {0:N2} GiB" -f ($freeBefore / 1GB))

if ($freeBefore -lt 2GB) {
    throw "Less than 2 GiB free. Refusing to download the P0-A shard."
}

Write-Host ""
Write-Host "Stage 2/2: index gate PASS; downloading only $shard."
Write-Host "The full 37.5 GB checkpoint remains blocked."

& hf download $repo $shard --local-dir $Destination
if ($LASTEXITCODE -ne 0) {
    throw "hf shard download failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Downloaded P0-A files:"
Get-ChildItem $Destination | Sort-Object Name | Select-Object Name, Length

$freeAfter = (Get-PSDrive -Name $driveName).Free
Write-Host ""
Write-Host ("Remaining free space: {0:N2} GiB" -f ($freeAfter / 1GB))
Write-Host "P0-A minimal asset set complete."
