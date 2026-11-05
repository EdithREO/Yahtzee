$ErrorActionPreference = 'Stop'
$godot = 'F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$project = Split-Path $PSScriptRoot -Parent
$folder = Join-Path $env:TEMP ('YachtDuel-physics-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $folder | Out-Null
$log = Join-Path $folder 'test.log'
$proc = Start-Process -FilePath $godot -ArgumentList @('--headless','--path',('"'+$project+'"'),'--script','res://room/physics_test.gd','--fixed-fps','60','--log-file',('"'+$log+'"')) -WindowStyle Hidden -PassThru -Wait
Get-Content -LiteralPath $log
Write-Host ('Test output: ' + $log)
if ($proc.ExitCode -ne 0) { throw 'Physics test failed. Inspect the log.' }
