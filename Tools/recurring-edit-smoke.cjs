const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync('Kairos/Kairos/Core/Resources/recurrence-engine.js','utf8'),ctx);
assert.equal(typeof ctx.kairosRecurringEditRequest,'function','Native recurring authoring is not implemented');
const rule={enabled:true,frequency:'daily',interval:1,startDate:'2026-11-01',mode:'fixed',endType:'count',count:10};
const task={id:'t',title:'Study',date:'2026-11-01',startTime:'09:00',endTime:'10:00',recurrence:{...rule,exceptions:{
 '2026-11-02':{status:'completed',completedAt:'saved',focusLoggedSeconds:1800,override:{checklist:[{id:'c',title:'Read',completed:true}]}},
 '2026-11-06':{override:{date:'2026-11-09',startTime:'13:00',endTime:'14:00'}},
 '2026-11-07':{focusLoggedSeconds:60,remainingMinutes:20,override:{checklist:[{id:'p',title:'Draft',completed:true}]}}
}}};
const call=r=>JSON.parse(ctx.kairosRecurringEditRequest(JSON.stringify(r)));
const before=JSON.stringify(task),request={task,day:'2026-11-05',scope:'future',changes:{startTime:'11:00',endTime:'12:00'},rule,newTaskID:'new'};
const result=call(request);assert.equal(result.tasks.length,2);assert.equal(result.tasks[0].recurrence.endDate,'2026-11-04');assert.equal(result.tasks[1].recurrence.count,6);
assert.equal(result.tasks[0].recurrence.exceptions['2026-11-02'].status,'completed');assert.equal(result.tasks[0].recurrence.exceptions['2026-11-06'].override.date,'2026-11-09');
assert.equal(result.tasks[0].recurrence.exceptions['2026-11-07'].override.checklist[0].completed,true);assert.equal(result.tasks[0].recurrence.exceptions['2026-11-07'].focusLoggedSeconds,60);
assert.equal(result.tasks[1].recurrence.exceptions['2026-11-07'].status,'deleted');assert.equal(result.tasks[1].focusLoggedSeconds,undefined);
const series=call({...request,scope:'series'});assert.equal(series.tasks[0].recurrence.exceptions['2026-11-02'].override.startTime,'09:00');
const single=call({...request,scope:'occurrence',changes:{date:'2026-11-08'}});assert.equal(single.tasks[0].recurrence.exceptions['2026-11-05'].override.date,'2026-11-08');assert.equal(single.tasks[0].recurrence.count,10);
assert.equal(call({...request,preview:true}).tasks,undefined);assert.equal(JSON.stringify(task),before);
assert.throws(()=>call({...request,rule:{...rule,interval:0}}));assert.throws(()=>call({...request,rule:{...rule,frequency:'weekly',weekdays:[]}}));
assert.throws(()=>call({...request,task:{...task,scheduleLocked:true}}));
assert.throws(()=>call({...request,changes:{startTime:'14:00',endTime:'13:00'}}));

const resetTask={...task,recurrence:{...rule,exceptions:{'2026-11-05':{override:{title:'Custom'}}}}};
assert.equal(call({task:resetTask,scope:'occurrence',day:'2026-11-05',changes:{title:'Study'}}).tasks[0].recurrence.exceptions['2026-11-05'].override,undefined);
const lockedDay={...request,scope:'occurrence',day:'2026-11-02'};
assert.throws(()=>call(lockedDay),/Completed schedules are locked/);
assert.equal(call({...lockedDay,allowCompleted:true}).tasks[0].recurrence.exceptions['2026-11-02'].override.startTime,'11:00');
const preset=call({scope:'seed',task:{recurrence:{enabled:true,preset:'weekdays',startDate:'2026-11-07'}}});assert.equal(preset.rule.frequency,'weekly');assert.deepEqual(preset.rule.weekdays,[1,2,3,4,5]);
const exhausted=call({...request,day:'2026-11-10',rule:{...rule,endType:'date',endDate:'2026-11-04'}});assert.equal(exhausted.tasks.length,1);
const weekly={id:'w',title:'Weekdays',recurrence:{...rule,frequency:'weekly',weekdays:[1,2,3,4,5],startDate:'2026-11-07'}};
assert.equal(call({task:weekly,rule:weekly.recurrence,day:'2026-11-07',scope:'series',changes:{title:'Study'}}).tasks[0].title,'Study');
const first=call({...request,day:'2026-11-01'});assert.equal(first.tasks[0].recurrence.endDate,'2026-10-31');assert.equal(first.tasks[1].recurrence.count,10);
const monthly=call({scope:'seed',task:{id:'m',recurrence:{enabled:true,frequency:'monthly',startDate:'2026-11-07'}}});assert.equal(monthly.rule.monthDay,7);
const leapRule={...rule,frequency:'yearly',month:2,monthDay:29,startDate:'2026-01-01',endType:'never',count:null};const leap=call({scope:'create',task:{id:'l',title:'Leap'},day:'2026-01-01',rule:leapRule,changes:{title:'Leap'}});assert.equal(leap.preview.after[0].date,'2028-02-29');
const shifting={id:'shift',title:'Shift',recurrence:{...rule,startDate:'2026-11-07',count:3}};
assert.deepEqual(call({task:shifting,scope:'series',day:'2026-11-07',rule:{...shifting.recurrence,startDate:'2026-11-01'},changes:{}}).preview.after.map(x=>x.date),['2026-11-01','2026-11-02','2026-11-03']);

console.log('Recurring authoring: scopes, count, moved/completed/checklist/focus preservation, validation and preview purity passed');
