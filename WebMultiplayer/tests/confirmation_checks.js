const vm=require('vm'),fs=require('fs'),assert=require('node:assert/strict');
class Element{constructor(){this.value='';this.textContent='';this.dataset={}}querySelector(){return new Element}replaceChildren(){}appendChild(){}append(){}add(){}setAttribute(){}}
const elements=new Map,connections=[];
class Socket{static OPEN=1;static CONNECTING=0;constructor(){this.readyState=1;connections.push(this)}send(){}close(){}}
const store=new Map;
const context={window:{},document:{getElementById:id=>{if(!elements.has(id))elements.set(id,new Element);return elements.get(id)},createElement:()=>new Element,querySelectorAll:()=>[],body:{classList:{toggle(){}}}},WebSocket:Socket,location:{protocol:'http:',host:'127.0.0.1:8765'},sessionStorage:{getItem:k=>store.get(k)??null,setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)},requestAnimationFrame(){},setInterval(){},setTimeout(){},clearTimeout(){},performance:{now:()=>1000},Option:class{},console};
vm.createContext(context);vm.runInContext(fs.readFileSync('F:/GA/YachtDuel/WebMultiplayer/source/room/app.js','utf8'),context);
const socket=connections[0];socket.onopen();socket.onmessage({data:JSON.stringify({type:"joined",seat:0,code:"000000",token:"fixture-only",last_request:0})});
const game=revision=>({score_revision:revision,turn_id:revision+1,over:false,busy:false,current_player:0,rolls:0,held:[false,false,false,false,false],values:[0,0,0,0,0],scores:[Array(12).fill(null),Array(12).fill(null)],categories:Array(12).fill('项目'),previews:Array(12).fill(null),totals:[0,0]});
const state=revision=>socket.onmessage({data:JSON.stringify({type:'state',game:game(revision),online:[true,true],started:true,code:'000000',restart:null})});
const count=()=>context.window.yachtConsume().ui.score_sound_event;
state(4);assert.equal(count(),0);state(4);assert.equal(count(),0);
socket.onmessage({data:JSON.stringify({type:'error',message:'操作拒绝'})});assert.equal(count(),0);
state(5);assert.equal(count(),1);state(5);assert.equal(count(),1);
socket.onopen();state(6);assert.equal(count(),1);state(7);assert.equal(count(),2);
state(0);state(1);assert.equal(count(),3);
console.log('CONFIRMATION_CHECKS passed: fresh restore, repeat, rejected request, successful revision, reconnect baseline, new match');
