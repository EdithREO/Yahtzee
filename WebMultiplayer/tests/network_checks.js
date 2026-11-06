const assert=require('node:assert/strict'),fs=require('node:fs');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));let checks=0;
function check(ok,name){assert.ok(ok,name);checks++;console.log('PASS '+name)}
class Peer{
 constructor(){this.ws=new WebSocket('ws://127.0.0.1:18766/ws');this.q=[];this.seq=0;this.ws.onmessage=e=>this.q.push(JSON.parse(e.data));}
 async ready(){const end=Date.now()+5000;while(this.ws.readyState!==1){if(Date.now()>end)throw Error('Connect timeout');await sleep(10)}}
 send(d){this.ws.send(JSON.stringify(d))}
 async take(fn){const end=Date.now()+20000;while(Date.now()<end){const i=this.q.findIndex(fn);if(i>=0)return this.q.splice(i,1)[0];await sleep(10)}throw Error('Message timeout')}
 async act(type,turn,extra={}){this.send({type,turn_id:turn,request_id:++this.seq,...extra});const d=await this.take(x=>x.type==='ack'||x.type==='error');assert.equal(d.type,'ack',d.message)}
}
(async()=>{
 const a=new Peer,b=new Peer;let resumed;
 try{
  await Promise.all([a.ready(),b.ready()]);a.send({type:'create'});const ja=await a.take(x=>x.type==='joined');b.send({type:'join',code:ja.code});await b.take(x=>x.type==='joined');a.send({type:'start'});
  const initial=(await a.take(x=>x.type==='state'&&x.game)).game;await b.take(x=>x.type==='state'&&x.game);
  let actor=initial.current_player===0?a:b,seat=initial.current_player,other=actor===a?b:a;
  actor.send({type:'roll',request_id:++actor.seq,turn_id:1});
  check((await actor.take(x=>x.type==='error')).message.includes('技能'),'roll blocked until both players choose');
  await a.act('select_skill',1,{skill_id:'d4'});
  await b.act('select_skill',1,{skill_id:'blackout'});
  const [readyA,readyB]=await Promise.all([a,b].map(peer=>peer.take(x=>x.type==='state'&&x.game?.skills_ready)));
  check([readyA,readyB].every(s=>JSON.stringify(s.game.selected_skills)===JSON.stringify(['d4','blackout'])),'both peers receive locked skill choices');
  other.send({type:'commit_score',request_id:++other.seq,turn_id:1,category:0});check((await other.take(x=>x.type==='error')).type==='error','spectator score request rejected');
  const last=[-1,-1];
  for(let turn=1;turn<=2;turn++){
   if(seat===0){
    await actor.act('use_d4',turn,{indices:[0,1]});
    actor.send({type:'use_d4',request_id:++actor.seq,turn_id:turn,indices:[2,3]});
    check((await actor.take(x=>x.type==='error')).type==='error','four-sided skill can only be used once');
   }else{
    await actor.act('use_blackout',turn);
    const warned=await other.take(x=>x.type==='state'&&x.game?.blackout_target===0);
    check(warned.game.blackout_dice.length===0,'opponent is warned before their dice are hidden');
    actor.send({type:'use_blackout',request_id:++actor.seq,turn_id:turn});
    check((await actor.take(x=>x.type==='error')).type==='error','blackout can only be used once');
   }
   await actor.act('roll',turn);
   const [ra,rb]=await Promise.all([a.take(x=>x.type==='roll_result'),b.take(x=>x.type==='roll_result')]);
   check(ra.result.ok&&JSON.stringify(ra.result.dice)===JSON.stringify(rb.result.dice),'identical real dice for turn '+turn);
   check(ra.result.dice.every(d=>d.d4===(seat===0&&d.id<2)&&(!d.d4||[4,5,6].includes(d.value))),'correct dice shapes and four-sided results for turn '+turn);
   const values=ra.result.dice.map(d=>d.value),category=[0,1,2,3,4,5].find(i=>!values.includes(i+1));
   await sleep(400);await actor.act('commit_score',turn,{category});last[seat]=category;
   const [sa,sb]=await Promise.all([a.take(x=>x.type==='state'&&x.game?.score_revision===turn),b.take(x=>x.type==='state'&&x.game?.score_revision===turn)]);
   check(sa.game.scores[seat][category]===0&&JSON.stringify(sa.game.last_scored)===JSON.stringify(last),'zero score and independent last choice persisted '+turn);
   check(JSON.stringify(sa.game.last_scored)===JSON.stringify(sb.game.last_scored),'both peers agree on highlights '+turn);
   const obscured=sa.game.blackout_dice;
   check(seat===1?new Set(obscured).size===3&&obscured.every(i=>i>=0&&i<5):obscured.length===0,'blackout applies only on the target turn');
   check(JSON.stringify(obscured)===JSON.stringify(sb.game.blackout_dice),'both peers agree on obscured dice');
   actor.send({type:'commit_score',request_id:actor.seq,turn_id:turn,category});check((await actor.take(x=>x.type==='error')).type==='error','duplicate confirmation rejected '+turn);
   [actor,other]=[other,actor];seat=1-seat;
  }
  a.ws.close();await b.take(x=>x.type==='state'&&!x.online[0]);resumed=new Peer;await resumed.ready();resumed.send({type:'resume',code:ja.code,token:ja.token});await resumed.take(x=>x.type==='joined');
  const restored=(await resumed.take(x=>x.type==='state'&&x.game?.score_revision===2)).game;
  check(JSON.stringify(restored.selected_skills)===JSON.stringify(['d4','blackout']),'reconnect restores both skill choices');
  check(restored.skill_used.every(Boolean),'reconnect restores skill use');
  check(restored.blackout_dice.length===(restored.current_player===0?3:0),'reconnect restores the current blackout');
  check(JSON.stringify(restored.last_scored)===JSON.stringify(last),'refresh/reconnect restores both last-score highlights');
  check(restored.scores[0][last[0]]===0&&restored.scores[1][last[1]]===0,'confirmed zero survives reconnection');
  resumed.send({type:'leave'});
  fs.writeFileSync('network-results.json',JSON.stringify({checks,last_scored:last,score_revision:2,zero_restored:true}));console.log('NETWORK_CHECKS passed '+checks);
 }finally{a.ws.close();b.ws.close();resumed?.ws.close()}
})().catch(e=>{console.error(e.stack);process.exitCode=1});
