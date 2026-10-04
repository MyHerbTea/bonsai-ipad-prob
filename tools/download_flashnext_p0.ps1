param(
    [string]$Destination = "D:\\models\\flashnext-p0"
)

$ErrorActionPreference = "Stop"
$repo = "neopolita/Qwen3.8-Flash-Next-102B-A5B-Niwaki-v2.4-3bit-mlx"

if (-not (Get-Command hf -ErrorAction SilentlyContinue)) {
    throw "Hugging Face CLI 'hf' was not found. Install/update huggingface_hub first."
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

Write-Host "Downloading only the FlashNext P0-A asset set."
Write-Host "The full 37.5 GB checkpoint is intentionally NOT downloaded."

& hf download $repo `
    model-00008-of-00008.safetensors `
    config.json `
    model.safetensors.index.json `
    niwaki_flash_load.py `
    tokenizer.json `
    tokenizer_config.json `
    vocab.json `
    chat_template.jinja `
    generation_config.json `
    --local-dir $Destination

if ($LASTEXITCODE -ne 0) {
    throw "hf download failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Downloaded files:"
Get-ChildItem $Destination | Sort-Object Name | Select-Object Name, Length

$root = [System.IO.Path]::GetPathRoot($Destination)
$driveName = $root.Substring(0, 1)
$free = (Get-PSDrive -Name $driveName).Free
Write-Host ""
Write-Host ("Remaining free space: {0:N2} GiB" -f ($free / 1GB))
Write-Host "P0-A asset download complete."
