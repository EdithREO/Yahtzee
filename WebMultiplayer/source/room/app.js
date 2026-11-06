'use strict';
const $ = id => document.getElementById(id);
const PLAYBACK_BUFFER_MS = 150; // Set between 100 and 200 for LAN testing.
let ws, seat = -1, state = null, reconnectTimer;
let scoreRevision = null, scoreSoundEvent = 0;
let lastReceived = 0, connectionReady = false;
function connectionNotice(message = '') {
  $('networkNotice').textContent = message;
  $('networkNotice').hidden = !message;
}
let game = null, pending = false, requestSequence = Number(sessionStorage.getItem('yacht_request_seq')||0), displayedTurn = 0;
let packets = [], offset = 0, rtt = 0, bestRtt = Infinity, currentRoll = '', rolling = false, requestAt = 0, startAt = 0, latestFinal = null, serverMetrics = '', syncMetrics = '';
window.yachtViewerReady = false;
window.yachtUiAction=(type,index=-1)=>{
 if(type==='select_skill'){
  if(canSelectSkill()) sendGameRequest(type,{skill_id:index});
  return;
 }
 if(type==='use_d4'){
  if(game?.selected_skills?.[seat]==='d4' && !game.skill_used[seat] && game.rolls<3) action(type,{indices:index});
  return;
 }
 if(type==='use_blackout'){
  if(game?.selected_skills?.[seat]==='blackout' && !game.skill_used[seat]) action(type);
  return;
 }
 if(type==='use_biohazard'){
  if(game?.selected_skills?.[seat]==='biohazard' && !game.skill_used[seat] && game.rolls<2) action(type,{index});
  return;
 }
 if(type==='restart_request'||type==='restart_reply'){
  if(!game?.skills_ready||game.busy||pending)return;
  requestSequence++;sessionStorage.setItem('yacht_request_seq',String(requestSequence));pending=true;
  send({type,request_id:requestSequence,turn_id:game.turn_id,...(type==='restart_reply'?{accept:index===1}:{})});return;
 }
 if(type==='roll'){requestAt=performance.now();action('roll');}
 if(type==='hold')action('hold',{index,held:!game.held[index]});
 if(type==='commit_score')action('commit_score',{category:index});
};
const rafTimes=[]; let lastRaf=0;
function measureRaf(now) { if(lastRaf) {rafTimes.push(now-lastRaf);if(rafTimes.length>240)rafTimes.shift();} lastRaf=now;requestAnimationFrame(measureRaf); }
requestAnimationFrame(measureRaf);
window.yachtConsume = () => { const batch = packets; packets = []; return {packets:batch, now_ms:performance.now()+offset, buffer_ms:PLAYBACK_BUFFER_MS,ui:{score_sound_event:scoreSoundEvent,game,seat,can_act:canAct(),can_select_skill:canSelectSkill(),rolling,pending,error:$('error').textContent,restart:state?.restart??null}}; };
window.yachtReport = d => {
  if (d.final || d.failed) rolling=false;
  if (d.final) $('viewer').dataset.result=JSON.stringify({...d,values:d.values.map((value,index)=>diePoints(index,value))});
  if (d.first_display && startAt) $('network').textContent = (requestAt ? '请求→开始显示 ' + (performance.now()-requestAt).toFixed(0) : '收到开始→显示 '+(performance.now()-startAt).toFixed(0)) + ' ms';
  if (d.final) { $('values').textContent = '服务端点数：' + d.values.map((value,index)=>diePoints(index,value)).join(' · '); if (d.face_mismatches) $('error').textContent = '姿态点数核对失败！'; }
  if (d.failed) $('error').textContent = '服务端投掷失败，请重试。';
  updateControls();
  if (d.fps !== undefined) {
    const frameMean=rafTimes.reduce((a,b)=>a+b,0)/Math.max(1,rafTimes.length), sorted=[...rafTimes].sort((a,b)=>a-b), p95=sorted[Math.floor((sorted.length-1)*.95)]||0;
    $('performance').textContent = `浏览器 FPS ${(1000/Math.max(.01,frameMean)).toFixed(0)} / Godot ${d.fps} ｜浏览器帧均值 ${frameMean.toFixed(2)} / P95 ${p95.toFixed(2)} ms ｜RTT ${rtt.toFixed(1)} ms`;
    if (currentRoll && !d.finished) send({type:'playback_metrics',roll_id:currentRoll,playhead_ms:d.playhead_ms,rtt_ms:rtt});
  }
};
function enqueue(d) { packets.push(d); if(packets.length>120) packets.splice(0,packets.length-120); }
setInterval(() => {
  if(ws?.readyState===WebSocket.OPEN) {
    if(performance.now()-lastReceived>15000) { connectionReady=false;connectionNotice('服务器无响应，正在重新连接。');ws.close(); }
    else send({type:'ping',client_ms:performance.now()});
  }
  updateControls();
},2000);
const saved = () => { try { return JSON.parse(sessionStorage.getItem('yacht_room') || 'null'); } catch { return null; } };
const show = id => { document.body.classList.toggle('playing',id==='test'); for (const s of ['home','lobby','test']) $(s).hidden = s !== id; };
const send = obj => { if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj)); else $('error').textContent = '尚未连接，请稍候。'; };
function connect() {
  $('connection').textContent = '正在连接服务器…';
  ws = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws`);
  const opening = setTimeout(()=>{if(ws.readyState===WebSocket.CONNECTING)ws.close();},10000);
  ws.onopen = () => { scoreRevision=null; clearTimeout(opening);lastReceived=performance.now();bestRtt=Infinity;connectionReady=!saved();connectionNotice(saved()?'正在恢复原有座位…':''); $('connection').textContent = '服务器已连接'; send({type:'ping',client_ms:performance.now()}); const s = saved(); if (s) send({type:'resume', code:s.code, token:s.token}); };
  ws.onclose = () => { clearTimeout(opening);connectionReady=false;connectionNotice('与服务器连接已断开（网络中断或服务器已关闭），正在重试。服务器仍运行时，2分钟内可恢复原座位。');$('connection').textContent = '连接已断开，正在重试…'; $('start').disabled = true; pending=false;updateControls();clearTimeout(reconnectTimer); reconnectTimer = setTimeout(connect, 1500); };
  ws.onmessage = event => {
    lastReceived=performance.now();
    let d; try { d = JSON.parse(event.data); } catch { return; }
    if(d.type==='pong') { const now=performance.now(); rtt=now-d.client_ms; if(rtt<bestRtt) {bestRtt=rtt;offset=d.server_ms-(d.client_ms+now)/2;} return; }
    if(d.type==='roll_started') { currentRoll=d.roll_id; rolling=true; latestFinal=null; startAt=performance.now(); if(!Number.isFinite(bestRtt)) offset=d.server_ms-startAt; if(seat!==d.actor) requestAt=0; enqueue(d); $('values').textContent='投掷中…';updateControls(); return; }
    if(d.type==='board_state') {rolling=false;currentRoll='';latestFinal=null;enqueue(d);updateControls();return;}
    if(d.type==='ack') {pending=false;updateControls();return;}
    if(d.type==='roll_state') {enqueue(d);return;}
    if(d.type==='roll_result') {currentRoll=d.result.roll_id;latestFinal=d;enqueue(d); serverMetrics=`服务器物理帧均值 ${d.result.physics_frame_ms_mean.toFixed(3)} / 最大 ${d.result.physics_frame_ms_max.toFixed(3)} ms（全进程）｜轨迹 JSON 双端发送 ${(d.result.trajectory_payload_bytes_both/1024).toFixed(1)} KB`; $('messages').textContent=serverMetrics; return;}
    if(d.type==='sync_metrics') {syncMetrics=`双端播放差估计 ${d.difference_estimate_ms.toFixed(1)} ms（RTT误差参考 ±${d.rtt_bound_ms.toFixed(1)} ms）`; $('sync').textContent=syncMetrics;return;}
    if (d.type === 'error') {pending=false;updateControls(); $('error').textContent = d.message; if (d.message.includes('会话已过期') || d.message.includes('房间码无效') && saved()) { sessionStorage.removeItem('yacht_room');game=null;state=null;seat=-1;rolling=false;connectionReady=true;enqueue({type:'reset'});connectionNotice('原房间已结束或服务器已重启，请重新创建或加入房间。');show('home'); } return; }
    if (d.type === 'joined') { seat = d.seat;requestSequence=Math.max(requestSequence,d.last_request||0);sessionStorage.setItem('yacht_request_seq',String(requestSequence));sessionStorage.setItem('yacht_room', JSON.stringify({code:d.code, token:d.token})); $('error').textContent = ''; }
    if (d.type === 'left' || d.type === 'ended') { scoreRevision=null; sessionStorage.removeItem('yacht_room'); seat = -1; state = null;game=null;pending=false;displayedTurn=0;rolling=false;enqueue({type:'reset'});show('home'); $('error').textContent = d.message || ''; return; }
    if (d.type === 'state') {
      const revision=d.game?.score_revision??0;
      if(scoreRevision!==null && revision>scoreRevision) scoreSoundEvent++;
      scoreRevision=revision;
      connectionReady=true;connectionNotice(d.started&&!d.online.every(Boolean)?'对方已离线，等待重连（保留座位2分钟）。':'');
      state = d; $('error').textContent = ''; const count = d.online.filter(Boolean).length + '/2';
      $('roomcode').textContent = d.code; $('testcode').textContent = d.code; $('count').textContent = '在线玩家 ' + count; $('testcount').textContent = count + ' 在线';
      for (let i=0;i<2;i++) $('seat'+i).textContent = '玩家 ' + (i ? 'B' : 'A · 房主') + '　' + (d.online[i] ? '已加入' : '未在线');
      $('start').disabled = seat !== 0 || !d.online.every(Boolean); $('start').textContent = seat === 0 ? '开始游戏' : '等待房主开始';
      $('teststatus').textContent = d.online.every(Boolean) ? '双方在线' : '对方已离线，等待重连'; show(d.started ? 'test' : 'lobby');
      game=d.game;renderGame();
    }
    if (d.type === 'test') $('messages').textContent = '收到玩家 ' + (d.seat ? 'B' : 'A') + ' 的测试消息';
  };
}
$('create').onclick = () => send({type:'create'});
$('join').onclick = () => { const code = $('code').value.trim(); if (!/^\d{6}$/.test(code)) { $('error').textContent = '请输入六位数字房间码。'; return; } send({type:'join',code}); };
$('start').onclick = () => send({type:'start'}); $('send').onclick = () => send({type:'test'});
$('roll').onclick = () => {requestAt=performance.now();action('roll');};
$('commit').onclick = () => {if($('category').value!=='') action('commit_score',{category:Number($('category').value)});};
$('category').onchange=updateControls;
for(let i=0;i<5;i++){const b=document.createElement('button');b.id='hold'+i;b.onclick=()=>action('hold',{index:i,held:!game.held[i]});$('holds').appendChild(b);}
function canSelectSkill(){
 return !!(connectionReady && !pending && game?.selected_skills?.[seat]==='' && state?.online.every(Boolean) && ws?.readyState===WebSocket.OPEN);
}
function canAct(){return !!(connectionReady && game?.skills_ready && !game.over && !game.busy && !rolling && !pending && game.current_player===seat && state?.restart==null && state?.online.every(Boolean) && ws?.readyState===WebSocket.OPEN && window.yachtViewerReady);}
function updateControls(){
 const active=canAct(); $('roll').disabled=!active || game?.rolls>=(game?.roll_limit??3) || game?.held.every(Boolean);
 $('roll').textContent=!window.yachtViewerReady?'正在加载骰盘…':(game?.busy||rolling)?'投掷中…':game?.current_player===seat?'投骰':'观看对方投骰';
 for(let i=0;i<5;i++) $('hold'+i).disabled=!active || !game?.values[i];
 const canScore=active && game.rolls>0 && !game.values.includes(0);
 $('commit').disabled=!canScore || $('category').value===''; $('category').disabled=!canScore;
}
function sendGameRequest(type,extra){
 pending=true;
 requestSequence++;
 sessionStorage.setItem('yacht_request_seq',String(requestSequence));
 send({type,request_id:requestSequence,turn_id:game.turn_id,...extra});
 updateControls();
}
function action(type,extra={}){if(canAct()) sendGameRequest(type,extra);}
function diePoints(index,value){
 if(game?.blackout_dice?.includes(index)) return '?';
 return game?.biohazard?.infected.includes(index) ? '☣' : value;
}
function renderGame(){
 if(!game){updateControls();return;}
 if(displayedTurn!==game.turn_id){displayedTurn=game.turn_id;$('category').value='';$('sync').textContent='';$('values').textContent='等待本回合投掷';}
 $('turn').textContent=game.over?(game.winner===null||game.winner===-1?'对局结束 · 平局':'对局结束 · 玩家 '+(game.winner?'B':'A')+' 获胜'):`你是玩家 ${seat?'B':'A'} · 当前玩家 ${game.current_player?'B':'A'} · 已投 ${game.rolls}/${game.roll_limit??3} 次 · 回合 ${game.turn_id}`;
 for(let i=0;i<5;i++){const b=$('hold'+i);b.textContent=`骰 ${i+1}：${diePoints(i,game.values[i]||'—')}${game.held[i]?' · 已保留':''}`;b.setAttribute('aria-pressed',String(game.held[i]));}
 const selected=$('category').value;$('category').replaceChildren(new Option('请选择',''));
 const tbody=$('scores').querySelector('tbody');tbody.replaceChildren();
 game.categories.forEach((name,i)=>{const tr=document.createElement('tr');for(const v of [name,game.scores[0][i]??'—',game.scores[1][i]??'—']){const td=document.createElement('td');td.textContent=v;tr.appendChild(td);}tbody.appendChild(tr);if(game.scores[seat][i]===null){const value=game.previews[i];$('category').add(new Option(name+(value===null?'':` · ${value} 分`),String(i)));}});
 $('category').value=selected;for(let i=0;i<2;i++)$('total'+i).textContent=game.totals[i];updateControls();
}
document.querySelectorAll('.leave').forEach(b => b.onclick = () => send({type:'leave'}));
connect();
