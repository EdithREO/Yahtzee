param([Parameter(Mandatory=$true)][string]$Origin,[int]$Seconds=120)
$ErrorActionPreference='Stop'
$checks=0
function Check($ok,$message) { if(!$ok){throw $message};$script:checks++;Write-Output "PASS $message" }
function New-Client {
    $ws=[Net.WebSockets.ClientWebSocket]::new()
    $ws.Options.SetRequestHeader('Origin',$Origin)
    $cts=[Threading.CancellationTokenSource]::new(30000)
    try {[void]$ws.ConnectAsync([uri]($Origin.Replace('https:','wss:')+'/ws'),$cts.Token).GetAwaiter().GetResult()} finally {$cts.Dispose()}
    return @{ws=$ws;frames=@{};seq=0}
}
function Send($c,$data) {
    $bytes=[Text.Encoding]::UTF8.GetBytes(($data|ConvertTo-Json -Compress -Depth 30))
    [void]$c.ws.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
}
function Receive($c,$type) {
    $cts=[Threading.CancellationTokenSource]::new(30000)
    try {
        do {
            $stream=[IO.MemoryStream]::new()
            try {
                do {
                    $buf=[byte[]]::new(65536)
                    $result=$c.ws.ReceiveAsync([ArraySegment[byte]]::new($buf),$cts.Token).GetAwaiter().GetResult()
                    if($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close){throw 'WebSocket closed'}
                    $stream.Write($buf,0,$result.Count)
                } while (!$result.EndOfMessage)
                $message=[Text.Encoding]::UTF8.GetString($stream.ToArray())|ConvertFrom-Json
            } finally {$stream.Dispose()}
            if($message.type -eq 'error'){throw $message.message}
            if($message.type -eq 'roll_state'){$c.frames[[string]$message.state.seq]=$message|ConvertTo-Json -Compress -Depth 30}
        } while ($message.type -ne $type)
        return $message
    } finally {$cts.Dispose()}
}
$a=$null;$b=$null;$r=$null
try {
    $a=New-Client; $b=New-Client
    Send $a @{type='create'}; $ja=Receive $a 'joined'
    Send $b @{type='join';code=$ja.code}; $jb=Receive $b 'joined'
    Send $a @{type='start'}
    do {$sa=Receive $a 'state'} while (!$sa.started)
    do {$sb=Receive $b 'state'} while (!$sb.started)
    Check ($sa.game.current_player -eq $sb.game.current_player) 'same authoritative first player over WSS'
    $actor=if($sa.game.current_player -eq 0){$a}else{$b}
    Send $actor @{type='roll';request_id=1;turn_id=$sa.game.turn_id}
    $ra=Receive $a 'roll_result';$rb=Receive $b 'roll_result'
    Check ($ra.result.ok -and $rb.result.ok) 'real server physics completed over WSS'
    Check (($ra.result.dice|ConvertTo-Json -Compress -Depth 20) -ceq ($rb.result.dice|ConvertTo-Json -Compress -Depth 20)) 'all five final poses and values identical'
    Check ($a.frames.Count -gt 10 -and $a.frames.Count -eq $b.frames.Count) 'both peers received complete sampled trajectory'
    foreach($key in $a.frames.Keys){if($a.frames[$key] -cne $b.frames[$key]){throw "Trajectory differs at frame $key"}}
    Check $true 'every sampled frame identical between peers'
    $start=Get-Date; $pings=0; $maximum=0.0
    while(((Get-Date)-$start).TotalSeconds -lt $Seconds) {
        foreach($c in @($a,$b)) {
            $timer=[Diagnostics.Stopwatch]::StartNew();Send $c @{type='ping';client_ms=0};$null=Receive $c 'pong';$maximum=[Math]::Max($maximum,$timer.Elapsed.TotalMilliseconds);$pings++
        }
        Start-Sleep -Milliseconds 2000
    }
    Check ($a.ws.State -eq 'Open' -and $b.ws.State -eq 'Open') 'persistent WSS connections remained open'
    $b.ws.Abort();$b.ws.Dispose();$b=$null
    $r=New-Client;Send $r @{type='resume';code=$ja.code;token=$jb.token};$null=Receive $r 'joined';$restored=Receive $r 'state'
    Check ($restored.game.rolls -eq 1 -and ($restored.game.values -join ',') -eq (($rb.result.dice|ForEach-Object value) -join ',')) 'network loss restores original seat and authoritative dice'
    Send $a @{type='leave'}
    Write-Output ('PUBLIC_TEST_SUMMARY '+(@{checks=$checks;frames=$a.frames.Count;seconds=[Math]::Round(((Get-Date)-$start).TotalSeconds,1);pongs=$pings;max_ping_ms=[Math]::Round($maximum,1)}|ConvertTo-Json -Compress))
} finally {foreach($c in @($a,$b,$r)){if($c){$c.ws.Abort();$c.ws.Dispose()}}}
