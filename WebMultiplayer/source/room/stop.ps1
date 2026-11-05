$ErrorActionPreference='Stop'
$webHome=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$project=Join-Path $webHome 'project'
$hasher=[Security.Cryptography.SHA256]::Create()
try { $hash=[BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($project.ToLowerInvariant()))).Replace('-','') } finally { $hasher.Dispose() }
try { $signal=[Threading.EventWaitHandle]::OpenExisting('Local\YachtDuelStop-'+$hash) }
catch [Threading.WaitHandleCannotBeOpenedException] { Write-Host 'This project is not running.'; exit 0 }
try { [void]$signal.Set();Write-Host 'Stop requested. Game, web proxy and this tunnel will close.' } finally { $signal.Dispose() }
