param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
try {
    $project=Join-Path $PSScriptRoot 'project'
    $hasher=[Security.Cryptography.SHA256]::Create()
    try {$hash=[BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($project.ToLowerInvariant()))).Replace('-','')} finally {$hasher.Dispose()}
    $runtime=Join-Path $env:LOCALAPPDATA 'YachtDuel'
    $record=[IO.File]::ReadAllText((Join-Path $runtime ('server-version-'+$hash+'.json'))) | ConvertFrom-Json
    if(!(Get-Process -Id $record.godot_pid -ErrorAction SilentlyContinue)){throw 'Offline'}
    $url=[IO.File]::ReadAllText((Join-Path $runtime 'public-origin.txt')).Trim()
    if($url -notmatch '^https://[a-zA-Z0-9.-]+\.cpolar\.(cn|top|io|com)(:[0-9]+)?$'){throw 'Tunnel not ready'}
    $response=Invoke-WebRequest 'http://127.0.0.1:8765/' -UseBasicParsing -TimeoutSec 3
    if($response.StatusCode -ne 200 -or !$response.Content.Contains('快艇骰子')){throw 'Game not ready'}
    Write-Output "当前游戏地址：$url/"
    if(!$CheckOnly){Start-Process ($url+'/')}
} catch {
    Write-Host '服务器未启动，或公网隧道尚未就绪。请先运行 start_server.bat，等窗口显示 PUBLIC GAME 后重试。'
    exit 1
}
