// Vendored web assignment progress, remaining-work and session-order read models.
(function(){
function parseTime(value){
  if(!/^\d{1,2}:\d{2}$/.test(String(value||''))) return null;
  const [h,m]=String(value).split(':').map(Number);
  if(h<0||h>23||m<0||m>59) return null;
  return h*60+m;
}
function taskDurationMinutes(task={},fallback=60){
  const start=parseTime(task.startTime),end=parseTime(task.endTime);
  let duration=null;
  if(start!==null&&end!==null){ duration=(end-start+1440)%1440; if(duration===0) duration=1440; }
  if(duration===null&&Number.isFinite(Number(task.estimatedMinutes))&&Number(task.estimatedMinutes)>0) duration=Number(task.estimatedMinutes);
  if(duration===null&&Number.isFinite(Number(task.lastScheduledMinutes))&&Number(task.lastScheduledMinutes)>0) duration=Number(task.lastScheduledMinutes);
  if(duration===null) duration=fallback;
  return Math.max(1,Math.round(duration));
}
function validPlanningDate(value){return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value}
function planningTasks(state){return (state.boards||[]).filter(board=>!board.archived).flatMap(board=>(board.sections||[]).filter(section=>!section.archived).flatMap(section=>(section.tasks||[]).filter(task=>!task.archived).map(task=>({board,section,task}))))}

function taskRemainingMinutes(task){
 return Number.isInteger(task?.remainingMinutes)&&task.remainingMinutes>=1&&task.remainingMinutes<=1440?task.remainingMinutes:taskDurationMinutes(task);
}



const active=state=>planningTasks(state).map(entry=>entry.task);
const ordered=task=>task?.sessionOrder==='sequential';
function orderedSessionGroup(state,parentId){
 const tasks=active(state),parents=tasks.filter(task=>task.id===parentId);if(!parents.some(ordered))return null;
 const sessions=tasks.filter(task=>task.assignmentId===parentId).sort((a,b)=>a.sessionIndex-b.sessionIndex);
 const all=(state.boards||[]).flatMap(board=>(board.sections||[]).flatMap(section=>section.tasks||[])),ids=new Set(),indexes=new Set();
 if(parents.length!==1||parents[0].assignmentId||parents[0].recurrence?.enabled)throw Error('Review the assignment session order: the parent is ambiguous or recurring.');
 for(const task of sessions){
  if(!Number.isSafeInteger(task.sessionIndex)||task.sessionIndex<1||indexes.has(task.sessionIndex)||ids.has(task.id)||all.filter(item=>item.id===task.id).length!==1||task.recurrence?.enabled)throw Error('Review session order: use unique positive session numbers and ordinary tasks.');
  ids.add(task.id);indexes.add(task.sessionIndex);
 }
 return {parent:parents[0],sessions};
}
function assignmentReadiness(state){
 const tasks=active(state),result=new Map();
 for(const parent of tasks.filter(ordered)){
  let group;try{group=orderedSessionGroup(state,parent.id)}catch{for(const task of tasks.filter(task=>task.assignmentId===parent.id))result.set(task.id,{state:'review'});continue}
  let needsReschedule=false;try{assertAssignmentOrder(state,new Set([parent.id]))}catch{needsReschedule=true}
  let waiting=null;for(const task of group.sessions){result.set(task.id,{state:task.completed?'completed':waiting?'waiting':'ready',needsReschedule,...(waiting?{waitingFor:waiting.id,waitingTitle:String(waiting.title||'Earlier session')}:{} )});if(!task.completed&&!waiting)waiting=task}
 }
 return result;
}
// Wall-clock values compare sessions within the same profile timezone. Slot
// generation separately rejects DST gaps and elapsed-duration transitions.
function wallStart(task){const start=parseTime(task?.startTime);return validPlanningDate(task?.date)&&start!==null?Date.parse(task.date+'T00:00:00Z')+start*60000:null}
function wallEnd(task){const start=wallStart(task);return start===null?null:start+taskDurationMinutes(task)*60000}
function clockAfterSession(task,clock){
 const end=wallEnd(task);if(end===null)throw Error('Schedule the prerequisite session first, or reschedule the whole assignment.');
 const current=Date.parse(clock.date+'T'+clock.time+':00Z');
 // findPlanningSlot adds one minute before rounding; allow exact adjacency.
 const lower=Math.max(current,end-60000),iso=new Date(lower).toISOString();return {date:iso.slice(0,10),time:iso.slice(11,16)};
}
function orderedPlacementClock(state,task,clock){
 const group=task.assignmentId?orderedSessionGroup(state,task.assignmentId):null;if(!group)return clock;
 const preceding=group.sessions.filter(item=>!item.completed&&item.sessionIndex<task.sessionIndex).at(-1);return preceding?clockAfterSession(preceding,clock):clock;
}
function expandOrderedTaskIds(state,ids){
 const result=new Set(ids),tasks=active(state);
 for(const id of ids){const task=tasks.find(item=>item.id===id),group=task?.assignmentId?orderedSessionGroup(state,task.assignmentId):null;if(group)for(const later of group.sessions)if(later.sessionIndex>task.sessionIndex&&!later.completed&&!later.scheduleLocked)result.add(later.id)}
 return [...result];
}
function assertAssignmentOrder(state,parentIds=null){
 for(const parent of active(state).filter(task=>ordered(task)&&(!parentIds||parentIds.has(task.id)))){
  const group=orderedSessionGroup(state,parent.id);let previous=null;
  for(const task of group.sessions){if(task.completed)continue;const start=wallStart(task);if(previous&&start!==null&&(wallEnd(previous)===null||start<wallEnd(previous)))throw Error('Session order would be broken for "'+String(parent.title||'Assignment')+'". Review the prerequisite and later sessions in Planning.');previous=task}
 }
}
function validateAssignmentOrderChanges(before,after){
 const old=new Map(active(before).map(task=>[task.id,task])),affected=new Set(),fields=['date','startTime','endTime','assignmentId','sessionIndex'];
 for(const task of active(after)){
  const prior=old.get(task.id);
  if(task.sessionOrder!==prior?.sessionOrder)affected.add(task.id);
  if(task.assignmentId&&(!prior||fields.some(key=>task[key]!==prior[key])||taskDurationMinutes(task)!==taskDurationMinutes(prior))){affected.add(task.assignmentId);if(prior?.assignmentId)affected.add(prior.assignmentId)}
 }
 assertAssignmentOrder(after,affected);
}

const esc=value=>String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));

function assignmentProgressIndex(state,today){
 const entries=planningTasks(state),byId=new Map(),counts=new Map(),groups=new Map(),result=new Map(),readiness=assignmentReadiness(state);
 for(const board of state.boards||[])for(const section of board.sections||[])for(const task of section.tasks||[])counts.set(task.id,(counts.get(task.id)||0)+1);
 for(const entry of entries)if(counts.get(entry.task.id)===1)byId.set(entry.task.id,entry.task);
 for(const {task} of entries)if(task.assignmentId&&byId.has(task.id)&&byId.has(task.assignmentId)){
  if(!groups.has(task.assignmentId))groups.set(task.assignmentId,[]);groups.get(task.assignmentId).push(task);
 }
 for(const [parentId,sessions] of groups){
  const parent=byId.get(parentId);if(parent.assignmentId||parent.recurrence?.enabled)continue;
  sessions.sort((a,b)=>(a.sessionIndex||0)-(b.sessionIndex||0)||String(a.id).localeCompare(String(b.id)));
  const dueDate=validPlanningDate(parent.dueDate)?parent.dueDate:null;
  const summary={parentId,parentTitle:String(parent.title||'Assignment'),total:sessions.length,completed:sessions.filter(task=>task.completed).length,remainingMinutes:sessions.filter(task=>!task.completed).reduce((sum,task)=>sum+taskRemainingMinutes(task),0),dueDate,status:parent.completed?'Assignment marked complete':!dueDate?'No deadline':dueDate<today?'Overdue':dueDate===today?'Due today':'Due '+dueDate,lateSessions:sessions.filter(task=>!task.completed&&dueDate&&task.date>dueDate).length,sessions:sessions.map(task=>({id:task.id,title:String(task.title||'Session'),completed:!!task.completed,date:task.date||null,startTime:task.startTime||null,minutes:taskDurationMinutes(task)}))};
  summary.ordered=parent.sessionOrder==='sequential';summary.readyCount=sessions.filter(task=>readiness.get(task.id)?.state==='ready').length;summary.waitingCount=sessions.filter(task=>readiness.get(task.id)?.state==='waiting').length;
  summary.orderNeedsReview=sessions.some(task=>readiness.get(task.id)?.needsReschedule||readiness.get(task.id)?.state==='review');
  for(const row of summary.sessions)row.readiness=readiness.get(row.id)||null;
  result.set(parentId,summary);for(const task of sessions)result.set(task.id,{...summary,sessionIndex:task.sessionIndex||null,isSession:true,readiness:readiness.get(task.id)||null});
 }
 return result;
}

globalThis.kairosAssignmentProgress=json=>{const r=JSON.parse(json);if(!validPlanningDate(r.today))throw Error('Invalid profile date');return JSON.stringify(assignmentProgressIndex(r.state,r.today).get(r.taskID)||null);};
})();
