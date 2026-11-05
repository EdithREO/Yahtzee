'use strict';
const assert=require('node:assert/strict');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let checks=0;
function check(ok,msg){assert.ok(ok,msg);checks++;console.log('PASS '+msg);}
class Client{
 constructor(){this.ws=new WebSocket('ws://127.0.0.1:18766/ws');this.messages=[];this.seq=0;this.ws.onmessage=e=>{this.messages.push(JSON.parse(e.data));};}
 async ready(){while(this.ws.readyState!==WebSocket.OPEN)await sleep(10);}
 send(d){this.ws.send(JSON.stringify(d));}
 async take(fn,timeout=150000){const end=Date.now()+timeout;while(Date.now()<end){const i=this.messages.findIndex(fn);if(i>=0)return this.messages.splice(i,1)[0];await sleep(10);}throw Error('Timed out');}
 async action(type,turn,extra={},reject=false){await sleep(380);if(type==='roll'&&!reject)this.messages=this.messages.filter(m=>m.type!=='roll_result'&&m.type!=='roll_started');const d={type,request_id:++this.seq,turn_id:turn,...extra};this.send(d);const reply=await this.take(x=>x.type==='error'||x.type==='ack'&&x.request_id===d.request_id);check(reply.type===(reject?'error':'ack'),type+(reject?' rejected':' accepted'));return d;}
 async game(fn){return (await this.take(x=>x.type==='state'&&x.game&&fn(x.game))).game;}
 close(){this.ws.close();}
}
(async()=>{
 const a=new Client(),b=new Client();await Promise.all([a.ready(),b.ready()]);
 a.send({type:'create'});const ja=await a.take(x=>x.type==='joined');
 b.send({type:'join',code:ja.code});const jb=await b.take(x=>x.type==='joined');
 await a.take(x=>x.type==='state'&&x.online.every(Boolean));a.send({type:'start'});
 const initial=await a.game(g=>g.turn_id===1);await b.game(g=>g.turn_id===1);
 check([0,1].includes(initial.current_player),'server selected first player');
 let current=initial.current_player===0?a:b,other=current===a?b:a;
 await other.action('roll',1,{},true);
 const first=await current.action('roll',1);
 current.send(first);check((await current.take(x=>x.type==='error')).message.includes('重复'),'duplicate request rejected');
 await other.action('hold',1,{index:0,held:true},true);
 const r1=(await current.take(x=>x.type==='roll_result')).result;check(r1.ok,'first physical roll finished');
 await current.game(g=>g.rolls===1&&!g.busy);
 await current.action('hold',1,{index:0,held:true});await other.game(g=>g.held[0]);
 await current.action('hold',1,{index:-1,held:true},true);
 await current.action('hold',1,{index:1.5,held:true},true);
 await current.action('roll',1,{values:[6,6,6,6,6]},true);
 await current.action('roll',1);const r2=(await current.take(x=>x.type==='roll_result')).result;
 check(r2.ok,'second physical roll finished');check(Math.abs(r2.dice[0].position[0]-4.1)<0.001&&r1.dice[0].value===r2.dice[0].value,'held die kept authoritative pose and value');
 await current.game(g=>g.rolls===2&&!g.busy);
 for(let i=1;i<5;i++)await current.action('hold',1,{index:i,held:true});
 await current.action('roll',1,{},true);
 for(let i=1;i<5;i++)await current.action('hold',1,{index:i,held:false});
 await current.action('roll',1);const r3=(await current.take(x=>x.type==='roll_result')).result;check(r3.ok,'third physical roll finished');
 await current.game(g=>g.rolls===3&&!g.busy);await current.action('roll',1,{},true);
 await current.action('commit_score',1,{category:6});
 const next=await current.game(g=>g.turn_id===2);
 check(next.current_player===1-initial.current_player&&next.rolls===0&&!next.held.some(Boolean),'turn switched and count/holds reset');
 check(next.scores[initial.current_player][6]===r3.dice.reduce((n,d)=>n+d.value,0),'score computed from server dice');
 await current.action('hold',1,{index:0,held:true},true);
 [current,other]=[other,current];await current.action('roll',2);const rb=(await current.take(x=>x.type==='roll_result')).result;check(rb.ok,'other seat can now roll');
 const stable=await current.game(g=>g.turn_id===2&&g.rolls===1&&!g.busy);
 await current.action('hold',2,{index:2,held:true});
 const spectatorToken=other===a?ja:jb;other.close();await current.take(x=>x.type==='state'&&!x.online.every(Boolean));
 await current.action('hold',2,{index:1,held:true},true);
 let resumed=new Client();await resumed.ready();resumed.send({type:'resume',code:ja.code,token:spectatorToken.token});resumed.seq=(await resumed.take(x=>x.type==='joined')).last_request;
 const restored=await resumed.game(g=>g.turn_id===2&&g.held[2]);check(JSON.stringify(restored.values)===JSON.stringify(stable.values),'spectator reconnect restores dice, turn and holds');
 const actorToken=current===a?ja:jb;current.close();await resumed.take(x=>x.type==='state'&&!x.online.every(Boolean));
 const actor=new Client();await actor.ready();actor.send({type:'resume',code:ja.code,token:actorToken.token});const recovered=await actor.take(x=>x.type==='joined');actor.seq=recovered.last_request;
 const actorState=await actor.game(g=>g.turn_id===2&&g.held[2]);check(actorState.rolls===1&&actorState.current_player===1-initial.current_player,'active player refresh preserves control and roll count');
 await actor.action('commit_score',2,{category:0});await resumed.game(g=>g.turn_id===3);
  await actor.action('restart_request',3);await resumed.take(x=>x.type==='state'&&x.restart!==null);
 await actor.action('restart_reply',3,{accept:true},true);
 await resumed.action('restart_reply',3,{accept:false});const unchanged=await actor.game(g=>g.turn_id===3);check(unchanged.scores.some(row=>row.some(v=>v!==null)),'restart declined preserves scores');
 await actor.action('restart_request',3);await resumed.take(x=>x.type==='state'&&x.restart!==null);
 await resumed.action('restart_reply',3,{accept:true});const fresh=await actor.game(g=>g.turn_id===4);check(fresh.rolls===0&&fresh.scores.every(row=>row.every(v=>v===null)),'mutual consent clears scores only after approval');
 actor.send({type:'leave'});await resumed.take(x=>x.type==='ended');check(true,'explicit exit closes match for both clients');
 actor.close();resumed.close();console.log('TURN_NETWORK_SUMMARY '+JSON.stringify({checks,first_player:initial.current_player,held_pose_preserved:true,reconnect:true}));
 process.exit(0);
})().catch(e=>{console.error(e.stack);process.exit(1);});
