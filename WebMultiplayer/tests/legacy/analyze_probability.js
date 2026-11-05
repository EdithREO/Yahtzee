'use strict';
const fs=require('node:fs');
const log=fs.readFileSync(process.argv[2],'utf8');
const line=log.split(/\r?\n/).find(l=>l.startsWith('PROBABILITY_SUMMARY '));
if(!line)throw Error('No completed probability summary');
const report=JSON.parse(line.slice('PROBABILITY_SUMMARY '.length));
const logGamma=Math.log(3*Math.sqrt(Math.PI)/4);
function q(x){
 const a=2.5;if(x===0)return 1;const factor=Math.exp(-x+a*Math.log(x)-logGamma);
 if(x<a+1){let sum=1/a,d=sum,ap=a;for(let i=1;i<1000;i++){d*=x/(++ap);sum+=d;if(Math.abs(d)<Math.abs(sum)*1e-14)break;}return Math.max(0,1-sum*factor);}
 let b=x+1-a,c=1e300,d=1/b,h=d;for(let i=1;i<1000;i++){const an=-i*(i-a);b+=2;d=an*d+b;if(Math.abs(d)<1e-300)d=1e-300;c=b+an/c;if(Math.abs(c)<1e-300)c=1e-300;d=1/d;const delta=d*c;h*=delta;if(Math.abs(delta-1)<1e-14)break;}return Math.min(1,Math.max(0,factor*h));
}
const analyze=counts=>{const n=counts.reduce((a,b)=>a+b,0),expected=n/6,chi_square=counts.reduce((sum,c)=>sum+(c-expected)**2/expected,0);return{n,counts,percentages:counts.map(c=>c/n*100),expected,chi_square,p_value:q(chi_square/2)};};
assertApprox(q(11.0704976935/2),0.05,1e-8);
function assertApprox(a,b,tolerance){if(Math.abs(a-b)>tolerance)throw Error('Chi-square numerical reference check failed');}
const dice=report.counts.map(analyze),pooled=analyze(report.counts[0].map((_,i)=>report.counts.reduce((n,row)=>n+row[i],0)));
const result={...report,dice,pooled,per_die_alpha:0.01,per_die_bonferroni_family_alpha:0.05,all_per_die_pass:dice.every(d=>d.p_value>=0.01),notes:'Pearson chi-square df=5. Five per-die tests use Bonferroni alpha=.01. Pooled p is descriptive because dice from the same throw can be correlated.'};
const output=process.argv[3];fs.writeFileSync(output,JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
if(process.argv[4]){
 const rows=dice.map((d,i)=>`|骰子 ${i+1}|${d.counts.join('|')}|${d.chi_square.toFixed(3)}|${d.p_value.toFixed(4)}|`).join('\n');
 const pooledRows=pooled.counts.map((n,i)=>`|${i+1}|${n}|${pooled.percentages[i].toFixed(3)}%|`).join('\n');
 const memoryDelta=report.after_5000.memory-report.baseline_after_250.memory;
 fs.writeFileSync(process.argv[4],`# 5000 次真实物理投掷统计\n\n实际尝试 ${report.attempts} 次，严格通过 ${report.successful} 次，失败 ${report.failures} 次，停稳/结果异常 ${report.invalid} 次；有效点数 ${pooled.n} 个。\n\n|骰子|1点|2点|3点|4点|5点|6点|卡方(df=5)|p值|\n|---|---:|---:|---:|---:|---:|---:|---:|---:|\n${rows}\n\n|点数|五骰合计次数|比例|\n|---|---:|---:|\n${pooledRows}\n\n零假设为各面概率均为1/6。五颗骰子分别检验，Bonferroni校正后每项显著性水平为0.01（家族水平0.05）；${result.all_per_die_pass?'本样本未发现显著偏离等概率的证据':'至少一颗骰子检出显著偏离，需继续排查'}。这不证明绝对公平、掷次独立或所有牌型概率均正确。五骰合并卡方 ${pooled.chi_square.toFixed(3)}、p=${pooled.p_value.toFixed(4)}仅作描述，同次骰子可能相关。\n\n使用正式服务端物理，水平冲量17–20，侧墙弹性0.80；每次重投全部五颗，无策略保留。固定60帧加速模拟，耗时 ${report.elapsed_seconds.toFixed(2)} 秒，累计模拟时间 ${report.simulation_seconds.toFixed(2)} 秒。物理恢复次数 ${report.recoveries}。第250至5000次Godot静态内存变化 ${memoryDelta} 字节，节点/对象/资源分别为 ${report.after_5000.nodes}/${report.after_5000.objects}/${report.after_5000.resources}；不代表进程工作集或长期泄漏证明。\n\n排查阶段首轮发现1次已落稳骰子被再次碰动但未复核速度；第二轮发现1次恢复冻结状态导致的120秒超时。两轮原始记录均保留。补充全组连续0.35秒停稳复核，并用故障注入tests冻结骰子重新参与物理后，另行完整运行本报告对应的最终5000次测试。\n`);
}
