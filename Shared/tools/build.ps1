param([ValidateSet('Native','Web','All')][string]$Target='All',[switch]$Export)
$ErrorActionPreference='Stop'
$layout=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$shared=Join-Path $layout 'Shared\source'
$engine=Join-Path $env:LOCALAPPDATA 'YachtDuel\tools\Godot\godot.windows.opt.tools.64.exe'
function Sync-Source($from,$to) {
    foreach($file in Get-ChildItem -LiteralPath $from -File -Recurse) {
        $relative=$file.FullName.Substring($from.Length).TrimStart('\')
        $destination=Join-Path $to $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}
foreach($kind in @('Native','Web')) {
    if($Target -ne 'All' -and $Target -ne $kind){continue}
    $targetHome=Join-Path $layout $(if($kind -eq 'Native'){'SinglePlayer'}else{'WebMultiplayer'})
    $project=Join-Path $targetHome 'project'
    New-Item -ItemType Directory -Force -Path $project | Out-Null
    Sync-Source $shared $project
    if($kind -eq 'Web') {
        Sync-Source (Join-Path $targetHome 'source') $project
        $publish=Join-Path $targetHome 'public'
        New-Item -ItemType Directory -Force -Path (Join-Path $publish 'viewer') | Out-Null
        foreach($name in @('index.html','app.js','style.css')){Copy-Item -LiteralPath (Join-Path $targetHome "source\room\$name") -Destination $publish -Force}
    }
    Copy-Item -LiteralPath (Join-Path $targetHome 'project.template.godot') -Destination (Join-Path $project 'project.godot') -Force
    Copy-Item -LiteralPath (Join-Path $targetHome 'export.template.cfg') -Destination (Join-Path $project 'export_presets.cfg') -Force
    [IO.File]::WriteAllText((Join-Path $project 'GENERATED.txt'),'Generated from shared canonical source. Do not edit this directory. Use the shared build script.')
    Write-Output "Synced $kind project: $project"
    if(!$Export){continue}
    if(!(Test-Path -LiteralPath $engine)){throw "Godot build tool not found: $engine"}
    # Godot can return exit 0 after failing to write project.binary. Check writable
    # export workspace first and validate the pack itself before publication.
    foreach($folder in @('cache','temp','feature_profiles')) {
        $workspace=Join-Path (Split-Path $engine -Parent) ('editor_data\'+$folder)
        New-Item -ItemType Directory -Force -Path $workspace | Out-Null
        $probe=Join-Path $workspace ('yacht-write-probe-'+$PID+'.tmp')
        [IO.File]::WriteAllText($probe,'write check')
        Remove-Item -LiteralPath $probe
    }
    $logs=Join-Path $targetHome 'build_logs'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    $exportStage=Join-Path $logs 'export_stage'
    New-Item -ItemType Directory -Force -Path $exportStage | Out-Null
    $artifact=Join-Path $exportStage $(if($kind -eq 'Native'){'YachtDuel.exe'}else{'index.html'})
    foreach($step in @('import','export')) {
        $arguments=@('--headless','--path',('"'+$project+'"'),'--log-file',('"'+(Join-Path $logs ($step+'.log'))+'"'))
        if($step -eq 'import'){$arguments+=@('--editor','--import','--quit')}
        else {$arguments+=@('--export-release',$(if($kind -eq 'Native'){'Windows'}else{'Web'}),('"'+$artifact+'"'))}
        $process=Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
        if($process.ExitCode -ne 0){throw "$kind $step failed. See $logs"}
        $fatal=@(Get-Content -LiteralPath (Join-Path $logs ($step+'.log')) | Where-Object {$_ -match '^(ERROR:|SCRIPT ERROR:)' -and $_ -notmatch 'Failed to read the root certificate store'})
        if($fatal.Count){throw "$kind $step logged an error: $($fatal[0]). See $logs"}
    }
    $pack=if($kind -eq 'Native'){$artifact}else{Join-Path $exportStage 'index.pck'}
    $validationLog=Join-Path $logs 'verify.log'
    $process=Start-Process -FilePath $engine -ArgumentList @('--headless','--main-pack',('"'+$pack+'"'),'--script',('"'+(Join-Path $PSScriptRoot 'verify_pack.gd')+'"'),'--log-file',('"'+$validationLog+'"')) -WindowStyle Hidden -PassThru -Wait
    if($process.ExitCode -ne 0 -or !(Select-String -LiteralPath $validationLog -Pattern '^PACK_VERIFY_OK:')){throw "$kind pack startup verification failed. Nothing was published. See $validationLog"}
    $destination=if($kind -eq 'Native'){Join-Path $targetHome 'Windows'}else{Join-Path $targetHome 'public\viewer'}
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path (Join-Path $exportStage '*') -Destination $destination -Force
    if($kind -eq 'Web') {
        $node=Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
        & $node (Join-Path $targetHome 'source\room\compress_viewer.js')
        if($LASTEXITCODE -ne 0){throw 'Web compression failed'}
    }
    $credits=Join-Path $shared 'audio\ATTRIBUTION.md'
    $creditsFolder=if($kind -eq 'Native'){Join-Path $targetHome 'Windows'}else{Join-Path $targetHome 'public'}
    Copy-Item -LiteralPath $credits -Destination (Join-Path $creditsFolder 'ATTRIBUTION.md') -Force
    Write-Output "Built $kind successfully."
}
