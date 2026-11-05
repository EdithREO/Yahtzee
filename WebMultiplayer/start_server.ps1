$ErrorActionPreference='Stop'
$layout=Split-Path $PSScriptRoot -Parent
& (Join-Path $layout 'Shared\tools\build.ps1') -Target Web
& (Join-Path $PSScriptRoot 'source\room\start.ps1') -Public
