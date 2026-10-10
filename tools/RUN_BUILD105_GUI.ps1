$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$runner=Join-Path $root 'rc126_build105_full_stage_certification.py'
if(-not (Test-Path -LiteralPath $runner)){Write-Host '[ERROR] Please extract full ZIP';exit 2}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object System.Windows.Forms.Form
$form.Text='Bonsai Build105 完整真机自动验收'
$form.ClientSize=New-Object System.Drawing.Size(580,300)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false
$form.Font=New-Object System.Drawing.Font('Microsoft YaHei UI',10)
$title=New-Object System.Windows.Forms.Label
$title.Text='Build105 只需输入一次 API Key'
$title.SetBounds(20,14,530,30);$form.Controls.Add($title)
$lab=New-Object System.Windows.Forms.Label
$lab.Text='API URL（可留空自动发现）'
$lab.SetBounds(20,54,520,24);$form.Controls.Add($lab)
$url=New-Object System.Windows.Forms.TextBox
$url.SetBounds(20,80,536,27);$form.Controls.Add($url)
$kl=New-Object System.Windows.Forms.Label
$kl.Text='API Key：Ctrl+V 或点击粘贴按钮'
$kl.SetBounds(20,116,530,23);$form.Controls.Add($kl)
$key=New-Object System.Windows.Forms.TextBox
$key.SetBounds(20,143,405,28);$key.UseSystemPasswordChar=$true;$form.Controls.Add($key)
$paste=New-Object System.Windows.Forms.Button
$paste.Text='粘贴';$paste.SetBounds(438,142,118,30)
$paste.Add_Click({
 try {
  $v=[System.Windows.Forms.Clipboard]::GetText().Trim()
  if($v -match '^(?i:Bearer)\s+(.+)$'){$v=$Matches[1].Trim()}
  $key.Text=$v
 }catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'粘贴失败')|Out-Null}
});$form.Controls.Add($paste)
$show=New-Object System.Windows.Forms.CheckBox
$show.Text='显示 API Key';$show.SetBounds(20,183,250,24)
$show.Add_CheckedChanged({$key.UseSystemPasswordChar=-not $show.Checked})
$form.Controls.Add($show)
$hint=New-Object System.Windows.Forms.Label
$hint.Text='Key 不写入报告；请先在 iPad 启动 API。'
$hint.SetBounds(20,220,540,25);$form.Controls.Add($hint)
$go=New-Object System.Windows.Forms.Button
$go.Text='开始完整测试';$go.SetBounds(305,260,158,32)
$go.Add_Click({
 if([string]::IsNullOrWhiteSpace($key.Text)){[System.Windows.Forms.MessageBox]::Show('请粘贴 API Key')|Out-Null;return}
 if($url.Text.Trim() -and $url.Text.Trim() -notmatch '^https?://[^\s]+$'){
  [System.Windows.Forms.MessageBox]::Show('API URL 格式无效')|Out-Null;return
 }
 $form.DialogResult=[System.Windows.Forms.DialogResult]::OK;$form.Close()
});$form.Controls.Add($go);$form.AcceptButton=$go
$cancel=New-Object System.Windows.Forms.Button
$cancel.Text='取消';$cancel.SetBounds(478,260,78,32)
$cancel.Add_Click({$form.DialogResult=[System.Windows.Forms.DialogResult]::Cancel;$form.Close()})
$form.Controls.Add($cancel);$form.CancelButton=$cancel
$result=$form.ShowDialog()
if($result -ne [System.Windows.Forms.DialogResult]::OK){$form.Dispose();exit 2}
$env:BONSAI_API_KEY=$key.Text.Trim()
if($url.Text.Trim()){$env:BONSAI_BASE_URL=$url.Text.Trim()}
$form.Dispose()
$exe=$null;$py=@()
if(Get-Command 'py.exe' -ErrorAction SilentlyContinue){$exe='py.exe';$py=@('-3','-u')}
elseif(Get-Command 'python.exe' -ErrorAction SilentlyContinue){$exe='python.exe';$py=@('-u')}
if(-not $exe){Write-Host '[ERROR] Python 3 is missing';Remove-Item Env:BONSAI_API_KEY;exit 2}
Write-Host 'Bonsai Build105 - API KEY [REDACTED]'
Write-Host '[PREFLIGHT] Testing Python compatibility before accessing iPad...'
$rc=2
try {
 & $exe @py $runner '--dry-run'
 if ($LASTEXITCODE -ne 0) {
   Write-Host '[ERROR] Local runner compatibility check failed before API test.'
   $rc=2
 } else {
   & $exe @py $runner '--output' (Join-Path $root 'RESULTS')
   $rc=$LASTEXITCODE
 }
}finally{
 Remove-Item Env:BONSAI_API_KEY -ErrorAction SilentlyContinue
 Remove-Item Env:BONSAI_BASE_URL -ErrorAction SilentlyContinue
}
exit $rc
