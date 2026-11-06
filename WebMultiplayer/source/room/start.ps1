param([switch]$RepairOnly,[switch]$Public)
$ErrorActionPreference = 'Stop'
$godot = 'F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$node = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
$webHome = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$project = Join-Path $webHome 'project'
$proxyScript = Join-Path $PSScriptRoot 'proxy.js'
$serverScript = Join-Path $project 'room\server.gd'

function Get-Listeners {
    @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -in @(8765,18766) })
}
function Get-Owner($processId) {
    Get-CimInstance Win32_Process -Filter ("ProcessId=" + $processId) -ErrorAction Stop
}
function Is-ProjectProcess($info) {
    if (!$info -or !$info.ExecutablePath -or !$info.CommandLine) { return $false }
    $expected = if ($info.ExecutablePath -ieq $node) { $proxyScript } elseif ($info.ExecutablePath -ieq $godot) { $serverScript } else { return $false }
    $pattern = '(?i)(?:^|\s)"?' + [regex]::Escape($expected) + '"?(?:\s|$)'
    return $info.CommandLine -match $pattern
}
function Remove-ProjectListeners {
    $owners = @(Get-Listeners | Select-Object -ExpandProperty OwningProcess -Unique)
    # Validate every owner before stopping any process.
    foreach ($ownerId in $owners) {
        $info = Get-Owner $ownerId
        if (!(Is-ProjectProcess $info)) { throw "Port occupied by an unverified process (PID $ownerId). No unrelated process was stopped." }
    }
    foreach ($ownerId in $owners) {
        if (!(Is-ProjectProcess (Get-Owner $ownerId))) { throw 'Process identity changed during cleanup.' }
        Stop-Process -Id $ownerId -ErrorAction Stop
    }
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Listeners).Count -gt 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ((Get-Listeners).Count -gt 0) { throw 'Port still occupied after cleanup.' }
}
if ($RepairOnly) {
    try { Remove-ProjectListeners; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }
}
if (!(Test-Path -LiteralPath $godot)) { throw "Godot not found: $godot" }
if (!(Test-Path -LiteralPath $node)) { throw "Node.js not found: $node" }
$hasher = [Security.Cryptography.SHA256]::Create()
$hash = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($project.ToLowerInvariant()))).Replace('-','')
$hasher.Dispose()
$mutex = New-Object Threading.Mutex($false, ('Local\YachtDuelRoom-' + $hash))
$locked = $false
$stopEvent = $null
$job = [IntPtr]::Zero
$godotProcess = $null; $nodeProcess = $null; $tunnelProcess = $null
$publicDir = Join-Path $env:LOCALAPPDATA 'YachtDuel'
$originFile = Join-Path $publicDir 'public-origin.txt'
$tunnelLog = Join-Path $publicDir ('cpolar-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
$versionFile = Join-Path $publicDir ('server-version-'+$hash+'.json')
function Get-ServerFingerprint {
    $digest = [Security.Cryptography.SHA256]::Create()
    try {
        $parts = foreach ($relative in @('room\server.gd','room\physics_world.gd','room\match_state.gd','room\dice_stack_assist.gd','room\d4_dice.gd','rules.gd','match_skills.gd','room\proxy.js','room\start.ps1','addons\dice_3d\dice_die_3d.gd','addons\dice_3d\dice_die_shape_3d.gd','addons\dice_3d\dice_roll_box_3d.gd')) {
            $file = Join-Path $project $relative
            '{0}:{1}' -f $relative,[BitConverter]::ToString($digest.ComputeHash([IO.File]::ReadAllBytes($file))).Replace('-','')
        }
        return [BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join '|')))).Replace('-','')
    }
    finally { $digest.Dispose() }
}
$serverFingerprint = Get-ServerFingerprint
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (!$locked) {
        $runningVersion = $null
        try { $runningVersion = [IO.File]::ReadAllText($versionFile) | ConvertFrom-Json } catch {}
        if (!$runningVersion -or $runningVersion.fingerprint -ne $serverFingerprint) {
            Write-Warning 'The running server has OLD or unverified source. Updates are NOT loaded. Finish the match, run stop_server.bat, then start_server.bat. The current match was not interrupted.'
        }
        Write-Host 'This project is already running. Use its existing startup window; URL: http://127.0.0.1:8765/'
        if (Test-Path -LiteralPath $originFile) { Write-Host ([IO.File]::ReadAllText($originFile)) }
        return
    }
    $stopEvent = New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,('Local\YachtDuelStop-'+$hash))
    [void]$stopEvent.Reset()
    if (Test-Path -LiteralPath $originFile) { [IO.File]::WriteAllText($originFile,'') }
    $listeners = @(Get-Listeners)
    if ($listeners.Count -gt 0) {
        Write-Host 'Checking an older server instance...'
        $needsElevation = $false
        foreach ($ownerId in @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)) {
            $info = Get-Owner $ownerId
            if (!(Is-ProjectProcess $info)) {
                # A higher-integrity process may hide its path. Verify the served
                # application before asking an elevated copy to inspect it.
                if ($info.Name -ne 'node.exe' -or $info.CommandLine) { throw "Unknown port owner PID $ownerId. Stop that application manually." }
                $response = Invoke-WebRequest 'http://127.0.0.1:8765/app.js' -UseBasicParsing -TimeoutSec 3
                if ($response.Content -cne [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'app.js'))) { throw 'Port owner is not the current project. Nothing was stopped.' }
                $needsElevation = $true
            }
        }
        if ($needsElevation) {
            Write-Host 'Administrator confirmation is needed to inspect and stop the old elevated project server.'
            $repair = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-RepairOnly') -PassThru -Wait
            if ($repair.ExitCode -ne 0) { throw 'Old server cleanup was not completed.' }
        } else { Remove-ProjectListeners }
    }
    $candidates = @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { $_ -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' })
    if ($candidates.Count -eq 0) { throw 'No private IPv4 address with a default gateway found.' }
    if ($candidates.Count -gt 1) {
        for ($i=0;$i -lt $candidates.Count;$i++) { Write-Host ("{0}: {1}" -f ($i+1),$candidates[$i]) }
        $choice=0
        if (![int]::TryParse((Read-Host 'Select network number'),[ref]$choice) -or $choice -lt 1 -or $choice -gt $candidates.Count) { throw 'Invalid selection.' }
        $lanIp=$candidates[$choice-1]
    } else { $lanIp=$candidates[0] }
    Add-Type -Path (Join-Path $PSScriptRoot 'job.cs')
    $job=[YachtChildJob]::Create()
    New-Item -ItemType Directory -Force -Path $publicDir | Out-Null
    if ($Public) {
        $cpolar = Join-Path $publicDir 'tools\cpolar.exe'
        if (!(Test-Path -LiteralPath $cpolar)) { throw 'cpolar missing. See room/PUBLIC.md.' }
        New-Item -ItemType Directory -Force -Path $publicDir | Out-Null
        [IO.File]::WriteAllText($originFile,'')
        [IO.File]::WriteAllText($tunnelLog,'')
        $env:YACHT_PUBLIC_ORIGIN_FILE=$originFile
    } else { Remove-Item Env:YACHT_PUBLIC_ORIGIN_FILE -ErrorAction SilentlyContinue }
    $godotProcess=Start-Process -FilePath $godot -ArgumentList @('--headless','--path',('"'+$project+'"'),'--script',('"'+$serverScript+'"')) -WindowStyle Hidden -PassThru
    [YachtChildJob]::Attach($job,$godotProcess.Handle)
    $env:YACHT_LAN_IPV4=$lanIp
    $nodeProcess=Start-Process -FilePath $node -ArgumentList ('"'+$proxyScript+'"') -WindowStyle Hidden -PassThru
    [YachtChildJob]::Attach($job,$nodeProcess.Handle)
    Start-Sleep -Seconds 2
    if ($godotProcess.HasExited -or $nodeProcess.HasExited) { throw 'Server failed to start.' }
    [IO.File]::WriteAllText($versionFile,(@{fingerprint=$serverFingerprint;godot_pid=$godotProcess.Id;proxy_pid=$nodeProcess.Id;started=(Get-Date).ToString('o')} | ConvertTo-Json -Compress))
    Write-Host ("LAN address: http://{0}:8765/" -f $lanIp)
    if ($Public) {
        $tunnelProcess=Start-Process -FilePath $cpolar -ArgumentList @('http','-proto=https','-region=cn_top','-inspect-addr=false','-log-level=INFO',('-log="'+$tunnelLog+'"'),'127.0.0.1:8765') -WindowStyle Hidden -PassThru
        [YachtChildJob]::Attach($job,$tunnelProcess.Handle)
        $publicWait = [Diagnostics.Stopwatch]::StartNew()
        Write-Host 'Waiting for cpolar HTTPS address...'
        Write-Host ("Public address file: {0}" -f $originFile)
    }
    Write-Host 'Press Enter to stop. Closing this window also stops game, proxy and this tunnel.'
    while ($true) {
        if ($stopEvent.WaitOne(0)) { break }
        if ($Public) {
            if ($tunnelProcess.HasExited) { throw 'cpolar exited. Bind your account using bind_cpolar.bat, then retry.' }
            # Read only URLs from the dedicated tunnel log; credentials stay outside the project.
            $dailyLog = Get-ChildItem -LiteralPath $publicDir -Filter ((Split-Path $tunnelLog -Leaf)+'.????????') -File | Sort-Object Name -Descending | Select-Object -First 1
            $logText = if ($dailyLog) { (Get-Content -LiteralPath $dailyLog.FullName -Tail 80) -join "`n" } else { '' }
            $urls = [regex]::Matches($logText,'Tunnel established at (https://[a-zA-Z0-9.-]+(?::[0-9]+)?)')
            if ($publicWait.IsRunning -and !$currentPublicUrl -and $publicWait.Elapsed.TotalSeconds -ge 45) {
                $publicWait.Stop()
                Write-Warning 'cpolar has not supplied a public URL after 45 seconds. LAN play is available. The launcher will keep checking for a public URL.'
                if ($dailyLog) { Write-Host ("Tunnel log: {0}" -f $dailyLog.FullName) }
            }
            if ($urls.Count -gt 0) {
                $candidate=$urls[$urls.Count-1].Groups[1].Value
                if ($candidate -match '^https://[a-zA-Z0-9.-]+\.cpolar\.(top|cn|io|com)(:[0-9]+)?$' -and $candidate -ne $currentPublicUrl) {
                    $currentPublicUrl=$candidate
                    [IO.File]::WriteAllText($originFile,$currentPublicUrl)
                    Write-Host ("PUBLIC GAME: {0}/" -f $currentPublicUrl)
                }
            }
        }
        if ($godotProcess.HasExited -or $nodeProcess.HasExited) { throw 'A server exited. Both processes will be cleaned up; launch again to retry.' }
        if (![Console]::IsInputRedirected -and [Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq [ConsoleKey]::Enter) { break }
        Start-Sleep -Milliseconds 100
    }
} finally {
    if ($job -ne [IntPtr]::Zero) { [void][YachtChildJob]::CloseHandle($job) }
    foreach ($p in @($tunnelProcess,$nodeProcess,$godotProcess)) {
        if ($null -ne $p -and !$p.HasExited) { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue }
    }
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    if ($null -ne $stopEvent) { $stopEvent.Dispose() }
    if ($Public -and $locked -and (Test-Path -LiteralPath $originFile)) { [IO.File]::WriteAllText($originFile,'') }
    if ($locked -and (Test-Path -LiteralPath $versionFile)) { Remove-Item -LiteralPath $versionFile }
}
