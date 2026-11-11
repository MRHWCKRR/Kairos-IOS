// Vendored web planning models: slot finding at bab6383; session commands, Undo, remaining work and order at e554ac6.
(function(){
const modules={},cache={};
function require(name){if(cache[name])return cache[name];const exports={};cache[name]=exports;modules[name](exports,require);return exports;}
modules["schedule-find-time-model.js"]=function(exports,require){
const {planningTasks,planningClock,validPlanningDate,shiftPlanningDate}=require("planning-model.js");
const {planningWindows,planningPlacementOccupancy,planningIntervalsConflict,planningBlockValid,planningDailyWork,planningDailyRemaining,validatePlanningRange}=require("planning-slots.js");
const {parseTime,formatTime,taskDurationMinutes}=require("schedule-utils.js");
const {generateTaskOccurrences,projectStoredOccurrence}=require("recurrence-utils.js");
const {stableStringify}=require("plan-merge.js");
const {savedPlanningPreferences}=require("planning-preferences.js");
const {savedWeeklyAvailability,normaliseWeeklyAvailability}=require("weekly-availability.js");
const {taskOverdueState}=require("schedule-overdue.js");

function findTimeTask(state,target,{recovery=false,clock}={}){
 const entries=planningTasks(state).filter(({task})=>String(task.id)===String(target?.taskId));
 if(entries.length!==1)throw Error('This task is missing, archived or ambiguous.');
 const entry=entries[0];let task=entry.task,occurrence=null;
 if(target.occurrenceDate){
  occurrence=generateTaskOccurrences(task,target.occurrenceDate,target.occurrenceDate)[0];
  if(!occurrence||occurrence.status!=='pending'||!recovery&&occurrence.mode!=='flexible')throw Error('Choose an unfinished flexible occurrence.');
  task=occurrence.task;
 }else if(task.recurrence?.enabled)throw Error('Choose a single recurring occurrence.');
 if(task.completed||task.scheduleLocked)throw Error('This task is completed or locked.');
 if(recovery){if(!clock||!taskOverdueState(task,clock,occurrence?.durationMinutes))throw Error('This task is no longer overdue.');}
 else if(task.date&&parseTime(task.startTime)!==null)throw Error('This task is already scheduled.');
 if(task.dueDate&&!validPlanningDate(task.dueDate))throw Error('Review the task deadline first.');
 const remembered=Number(task.lastScheduledMinutes);
 const duration=occurrence?.durationMinutes??(parseTime(task.startTime)===null&&Number.isInteger(remembered)&&remembered>0?remembered:taskDurationMinutes(task));
 if(!Number.isInteger(duration)||duration<1||duration>=1440)throw Error('Choose a task duration from 1 to 1439 minutes.');
 return {...entry,task,occurrence,duration};
}
function storedSchedule(task,date){const old=projectStoredOccurrence(task,date);return old?{date:old.displayDate,startTime:old.startTime,endTime:old.endTime,durationMinutes:old.durationMinutes}:{}}
// Completed blocks still occupy calendar space, even if the view hides them.
function occupiedState(state){return {...state,boards:(state.boards||[]).map(board=>({...board,sections:(board.sections||[]).map(section=>({...section,tasks:(section.tasks||[]).map(task=>({...task,completed:false,...(task.recurrence?.enabled?{recurrence:{...task.recurrence,exceptions:Object.fromEntries(Object.entries(task.recurrence.exceptions||{}).map(([date,exception])=>[date,exception.status==='completed'?{...exception,status:'pending',override:{...exception.override,...storedSchedule(task,date)}}:exception]))}}:{})}))}))}))}}
function otherWork(state,target){return {...state,boards:(state.boards||[]).map(board=>({...board,sections:(board.sections||[]).map(section=>({...section,tasks:(section.tasks||[]).flatMap(task=>String(task.id)!==String(target.taskId)?[task]:target.occurrenceDate?[{...task,recurrence:{...task.recurrence,exceptions:{...task.recurrence.exceptions,[target.occurrenceDate]:{status:'skipped'}}}}]:[])}))}))}}

function findTaskTimes(state,target,options,clock=planningClock(Date.now(),options.timezone)){
 validatePlanningRange(options.from,options.to);
 if(!validPlanningDate(clock.date)||parseTime(clock.time)===null)throw Error('Current planning time is unavailable.');
 const entry=findTimeTask(state,target,{recovery:options.recovery===true,clock}),{task,duration}=entry;
 const remaining=otherWork(state,target),afterDeadline=options.recovery===true&&task.dueDate&&task.dueDate<clock.date?task.dueDate:null;
 // Vacate only the reviewed placement. Other occurrences still reserve their time.
 const busy=planningPlacementOccupancy(occupiedState(options.recovery===true?remaining:state),options),dailyWork=planningDailyWork(remaining,options),cache=new Map(),slots=[];
 const signature=stableStringify({target,options,busy,boardId:entry.board.id,sectionId:entry.section.id,duration,date:task.date??null,startTime:task.startTime??null,endTime:task.endTime??null,dueDate:task.dueDate??null,assignmentId:task.assignmentId??null,dailyWork:[...dailyWork]});
 for(let date=options.from;date<=options.to;date=shiftPlanningDate(date,1)){
  if(date<clock.date||!options.recovery&&validPlanningDate(task.date)&&date<task.date||!afterDeadline&&task.dueDate&&date>task.dueDate||task.assignmentId&&duration>planningDailyRemaining(dailyWork,date,options))continue;
  for(const window of planningWindows(options,date)){
   let inGap=false;
   const earliest=Math.max(window.start,date===clock.date?parseTime(clock.time)+1:0);
   for(let start=Math.ceil(earliest/5)*5;start+duration<=window.end;start+=5){
    const candidate={date,startMin:start,endMin:start+duration};
    const fits=!busy.some(item=>planningIntervalsConflict(candidate,item,options,cache))&&planningBlockValid(date,start,duration,options.timezone||'UTC');
    if(fits&&!inGap)slots.push({date,startTime:formatTime(start,false),endTime:formatTime((start+duration)%1440,false)});
    inGap=fits;
   }
  }
 }
 const previousStart=parseTime(task.startTime);
 return {target:structuredClone(target),title:String(task.title||'Task'),duration,signature,slots,afterDeadline,previous:{date:task.date||null,startTime:task.startTime||null,endTime:previousStart===null?null:formatTime((previousStart+duration)%1440,false)}};
}

function assertFindTimePlacement(state,target,changes,placement,clock){
 if(!placement?.options||typeof placement.signature!=='string')throw Error('Review a new time preview.');
 const report=findTaskTimes(state,target,placement.options,clock);
 if(report.signature!==placement.signature||!report.slots.some(slot=>slot.date===changes.date&&slot.startTime===changes.startTime&&slot.endTime===changes.endTime))throw Error('The task, calendar or available time changed. Find a time again.');
 if(target.occurrenceDate&&changes.durationMinutes!==undefined&&changes.durationMinutes!==report.duration)throw Error('The occurrence duration changed. Review a new time.');
}
function assertFindTimeSettings(options,userData){
 const saved=savedPlanningPreferences(userData),weekly=savedWeeklyAvailability(userData),timezone=userData?.settings?.profile?.timezone||options.timezone;
 if(timezone!==options.timezone||saved.gapMinutes!==(options.gapMinutes??0)||saved.dailyLimitMinutes!==(options.dailyLimitMinutes??0)||stableStringify(weekly)!==stableStringify(normaliseWeeklyAvailability(options.weeklyAvailability)))throw Error('Your saved planning settings changed. Find a time again.');
}

Object.assign(exports,{findTimeTask,findTaskTimes,assertFindTimePlacement,assertFindTimeSettings});
};
modules["schedule-overdue.js"]=function(exports,require){
const {validPlanningDate,shiftPlanningDate}=require("planning-model.js");
const {parseTime,taskDurationMinutes}=require("schedule-utils.js");

function taskOverdueState(task,clock,duration=taskDurationMinutes(task)){
 if(!task||task.completed||task.archived)return null;
 if(validPlanningDate(task.dueDate)&&task.dueDate<clock.date)return 'deadline';
 if(!validPlanningDate(task.date))return null;
 const start=parseTime(task.startTime);
 if(start===null)return task.date<clock.date?'date':null;
 const end=start+duration,endDate=shiftPlanningDate(task.date,Math.floor(end/1440));
 return endDate<clock.date||endDate===clock.date&&end%1440<=parseTime(clock.time)?'schedule':null;
}

function scheduleBacklogItems(entries,occurrences,clock){
 const items=[];
 for(const entry of entries){
  const {task}=entry;if(task.recurrence?.enabled||task.completed||task.archived)continue;
  const overdueReason=taskOverdueState(task,clock);
  if(overdueReason||!validPlanningDate(task.date)||parseTime(task.startTime)===null)items.push({kind:'task',...entry,overdueReason});
 }
 for(const occurrence of occurrences){
  if(occurrence.status!=='pending')continue;
  const task={...occurrence.task,date:occurrence.displayDate},overdueReason=taskOverdueState(task,clock,occurrence.durationMinutes);
  if(overdueReason||occurrence.mode==='flexible'&&parseTime(occurrence.startTime??task.startTime)===null)items.push({kind:'occurrence',task,board:occurrence.board,section:occurrence.section,occurrence,overdueReason});
 }
 return items.sort((a,b)=>Number(!!b.overdueReason)-Number(!!a.overdueReason)||(a.overdueReason?String(a.overdueReason==='deadline'?a.task.dueDate:a.task.date).localeCompare(String(b.overdueReason==='deadline'?b.task.dueDate:b.task.date)):0));
}

Object.assign(exports,{taskOverdueState,scheduleBacklogItems});
};
modules["schedule-change-model.js"]=function(exports,require){
const {assertFindTimePlacement}=require("schedule-find-time-model.js");
const {stableStringify}=require("plan-merge.js");
const {parseTime,taskDurationMinutes}=require("schedule-utils.js");
const {normalizeRecurrence,projectStoredOccurrence,generateTaskOccurrences}=require("recurrence-utils.js");

const TASK_FIELDS=['date','startTime','endTime','estimatedMinutes','lastScheduledMinutes'];
const OCCURRENCE_FIELDS=['date','startTime','endTime','durationMinutes'];
const pick=(value,keys)=>Object.fromEntries(keys.filter(key=>Object.hasOwn(value||{},key)).map(key=>[key,structuredClone(value[key])]));
const validDate=value=>typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value;
function locate(state,target,{allowCompleted=false}={}){
 const found=(state.boards||[]).flatMap(board=>(board.sections||[]).flatMap(section=>(section.tasks||[]).filter(task=>String(task.id)===String(target?.taskId)).map(task=>({board,section,task}))));
 if(found.length!==1||found[0].board.archived||found[0].section.archived||found[0].task.archived)throw Error('This task is missing, archived or ambiguous.');
 const entry=found[0];
 if(target.occurrenceDate){
  if(!validDate(target.occurrenceDate))throw Error('Invalid occurrence date.');
  const occurrence=entry.task.recurrence?.exceptions?.[target.occurrenceDate]?.status==='completed'?projectStoredOccurrence(entry.task,target.occurrenceDate):generateTaskOccurrences(entry.task,target.occurrenceDate,target.occurrenceDate,{today:target.occurrenceDate})[0];
  if(!occurrence||!(occurrence.status==='pending'||allowCompleted&&occurrence.status==='completed'))throw Error('This occurrence changed or was completed.');
  return {...entry,occurrence};
 }
 if(entry.task.recurrence?.enabled||entry.task.completed&&!allowCompleted)throw Error('Choose an unfinished task or a single recurring occurrence.');
 return entry;
}
function fields(entry){
 if(!entry.occurrence)return {values:pick(entry.task,TASK_FIELDS)};
 const exception=entry.task.recurrence?.exceptions?.[entry.occurrence.occurrenceDate];
 return {values:pick(exception?.override,OCCURRENCE_FIELDS),exceptionPresent:!!exception,overridePresent:Object.hasOwn(exception||{},'override')};
}
function signature(entry){
 const rule=normalizeRecurrence(entry.task,entry.task.date);delete rule.exceptions;
 return stableStringify({schedule:fields(entry).values,template:entry.occurrence?pick(entry.task,TASK_FIELDS):null,
  effective:entry.occurrence?{date:entry.occurrence.displayDate,startTime:entry.occurrence.startTime,endTime:entry.occurrence.endTime,durationMinutes:entry.occurrence.durationMinutes}:null,
  completed:entry.task.completed===true,status:entry.occurrence?.status??null,scheduleLocked:entry.task.scheduleLocked===true,rule:entry.occurrence?rule:null});
}
function validateChanges(changes,occurrence){
 const allowed=occurrence?OCCURRENCE_FIELDS:['date','startTime','endTime','lastScheduledMinutes'];
 if(!changes||typeof changes!=='object'||Array.isArray(changes)||Object.keys(changes).some(key=>!allowed.includes(key))||!['date','startTime','endTime'].every(key=>Object.hasOwn(changes,key)))throw Error('Invalid schedule fields.');
 if(changes.date!==null&&!validDate(changes.date))throw Error('Choose a valid schedule date.');
 for(const key of ['startTime','endTime'])if(changes[key]!==null&&(typeof changes[key]!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(changes[key])))throw Error('Choose a valid time.');
 const start=parseTime(changes.startTime),end=parseTime(changes.endTime);
 if((start===null)!==(end===null)||start!==null&&(!changes.date||end!==0&&end<=start))throw Error('A task must end after it starts and by midnight.');
 const duration=changes.durationMinutes??changes.lastScheduledMinutes;
 if(duration!==undefined&&(!Number.isInteger(duration)||duration<1||duration>1440))throw Error('Choose a valid duration.');
 if(occurrence&&(!Number.isInteger(changes.durationMinutes)||start!==null&&((end-start+1440)%1440||1440)!==duration))throw Error('This occurrence duration does not match its times.');
}
function buildScheduleChange(state,target,changes,options={}){
 const entry=locate(state,target,options);validateChanges(changes,!!entry.occurrence);
 return {command:{type:'schedule_change',target:structuredClone(target),changes:structuredClone(changes)},expected:{boardId:entry.board.id,sectionId:entry.section.id,guard:signature(entry)}};
}
function check(entry,expected){
 if(entry.board.id!==expected?.boardId||entry.section.id!==expected?.sectionId||signature(entry)!==expected?.guard)throw Error('The task moved, its schedule changed or its status changed. Review the current task.');
}
function writeFields(entry,saved){
 if(!entry.occurrence){for(const key of TASK_FIELDS){if(Object.hasOwn(saved.values,key))entry.task[key]=structuredClone(saved.values[key]);else delete entry.task[key]}return}
 // Store explicit start/end overrides, including values equal to the template.
 // Flexible occurrences require an explicit startTime to become scheduled.
 const date=entry.occurrence.occurrenceDate,rule=normalizeRecurrence(entry.task,entry.task.date),exception=structuredClone(rule.exceptions[date]||{}),override={...exception.override};
 for(const key of OCCURRENCE_FIELDS){if(Object.hasOwn(saved.values,key))override[key]=structuredClone(saved.values[key]);else delete override[key]}
 if(Object.keys(override).length||saved.overridePresent)exception.override=override;else delete exception.override;
 if(Object.keys(exception).length||saved.exceptionPresent)rule.exceptions[date]=exception;else delete rule.exceptions[date];
 entry.task.recurrence=rule;
}
function applyScheduleChange(state,command,expected,options={}){
 const entry=locate(state,command.target,options);check(entry,expected);validateChanges(command.changes,!!entry.occurrence);
 if(command.placement)assertFindTimePlacement(state,command.target,command.changes,command.placement);
 const before=fields(entry),next=structuredClone(state),destination=locate(next,command.target,options);
 writeFields(destination,{...before,values:{...before.values,...command.changes}});
 const after=locate(next,command.target,options);
 return {next,result:{type:'schedule_change',task:after.task,scheduleUndo:{version:1,target:structuredClone(command.target),boardId:after.board.id,sectionId:after.section.id,guard:signature(after),before}}};
}
function applyScheduleUndo(state,record,options={}){
 if(record?.version!==1||!record.target||!record.before?.values||typeof record.guard!=='string')throw Error('This saved schedule Undo is unavailable.');
 const entry=locate(state,record.target,options);check(entry,record);
 const keys=entry.occurrence?OCCURRENCE_FIELDS:TASK_FIELDS;
 if(Object.keys(record.before.values).some(key=>!keys.includes(key)))throw Error('Invalid saved scheduling fields.');
 const next=structuredClone(state);writeFields(locate(next,record.target,options),record.before);
 return {next,result:{type:'schedule_undo',task:locate(next,record.target,options).task}};
}

Object.assign(exports,{buildScheduleChange,applyScheduleChange,applyScheduleUndo});
};
modules["planning-model.js"]=function(exports,require){
const {generateTaskOccurrences}=require("recurrence-utils.js");

function validPlanningDate(value){return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value}
function requireDate(value){if(!validPlanningDate(value))throw Error('Choose a valid date.');return value}
function shiftPlanningDate(date,days){requireDate(date);return new Date(Date.parse(date+'T12:00:00Z')+days*86400000).toISOString().slice(0,10)}
function planningWeekStart(date){requireDate(date);const day=new Date(date+'T12:00:00Z').getUTCDay();return shiftPlanningDate(date,-((day+6)%7))}
function planningClock(now=Date.now(),timezone='UTC'){
 const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(now)).filter(part=>part.type!=='literal').map(part=>[part.type,part.value]));
 return {date:`${parts.year}-${parts.month}-${parts.day}`,time:`${parts.hour}:${parts.minute}`};
}
function planningTasks(state){return (state.boards||[]).filter(board=>!board.archived).flatMap(board=>(board.sections||[]).filter(section=>!section.archived).flatMap(section=>(section.tasks||[]).filter(task=>!task.archived).map(task=>({board,section,task}))))}

function deadlineSummary(state,today){
 requireDate(today);
 return planningTasks(state).filter(({task})=>!task.completed&&!task.recurrence?.enabled).map(entry=>{
  const due=validPlanningDate(entry.task.dueDate)?entry.task.dueDate:null;
  return {...entry,dueDate:due,status:!due?'no-deadline':due<today?'overdue':due===today?'today':'upcoming',afterDeadline:!!due&&validPlanningDate(entry.task.date)&&entry.task.date>due};
 }).sort((a,b)=>(a.dueDate||'9999').localeCompare(b.dueDate||'9999')||String(a.task.title).localeCompare(String(b.task.title)));
}

function planningOccurrences(task,from,to,today=from){
 const byId=new Map(generateTaskOccurrences(task,from,to,{today}).map(item=>[item.occurrenceId,item]));
 for(const [logicalDate,exception] of Object.entries(task.recurrence?.exceptions||{})){
  const moved=exception?.override?.date;
  if(validPlanningDate(logicalDate)&&validPlanningDate(moved)&&moved>=from&&moved<=to&&(logicalDate<from||logicalDate>to)){
   const item=generateTaskOccurrences(task,logicalDate,logicalDate,{today})[0];if(item)byId.set(item.occurrenceId,item);
  }
 }
 return [...byId.values()].filter(item=>item.displayDate>=from&&item.displayDate<=to&&!['deleted','skipped'].includes(item.status));
}

function weeklyReview(state,weekStart,today){
 requireDate(today);const from=planningWeekStart(weekStart),to=shiftPlanningDate(from,6),items=[];
 for(const entry of planningTasks(state)){
  const task=entry.task;
  if(task.recurrence?.enabled){for(const occurrence of planningOccurrences(task,from,to,today))items.push({...entry,id:occurrence.occurrenceId,date:occurrence.displayDate,completed:occurrence.status==='completed',occurrenceDate:occurrence.occurrenceDate,title:occurrence.task.title})}
  else if(validPlanningDate(task.date)&&task.date>=from&&task.date<=to)items.push({...entry,id:task.id,date:task.date,completed:task.completed===true,title:task.title});
 }
 items.sort((a,b)=>a.date.localeCompare(b.date)||String(a.id).localeCompare(String(b.id)));
 const pending=items.filter(item=>!item.completed);
 return {from,to,completed:items.filter(item=>item.completed),pending,slipped:pending.filter(item=>item.date<today),nextDeadlines:deadlineSummary(state,today).filter(item=>item.dueDate>to&&item.dueDate<=shiftPlanningDate(to,7))};
}

Object.assign(exports,{validPlanningDate,shiftPlanningDate,planningWeekStart,planningClock,planningTasks,deadlineSummary,planningOccurrences,weeklyReview});
};
modules["planning-slots.js"]=function(exports,require){
const {eventSegmentsForDate}=require("schedule-events.js");
const {planningTasks,planningOccurrences,validPlanningDate,shiftPlanningDate}=require("planning-model.js");
const {parseTime,formatTime,taskDurationMinutes}=require("schedule-utils.js");
const {zonedTaskStart}=require("task-reminders.js");
const {normaliseWeeklyAvailability}=require("weekly-availability.js");

function validatePlanningRange(from,to){
 if(!validPlanningDate(from)||!validPlanningDate(to)||to<from||(Date.parse(to)-Date.parse(from))/86400000>=31)throw Error('Choose a valid date range of at most 31 days.');
}
function planningAvailability(input){
 planningGapMinutes(input);planningDailyLimit(input);
 if(input.availabilitySource==='saved'&&input.weeklyAvailability==null)throw Error('Your saved weekly availability changed. Review a new preview.');
 validatePlanningRange(input.from,input.to);const weekly=normaliseWeeklyAvailability(input.weeklyAvailability),start=weekly?0:parseTime(input.dayStart),end=weekly?1440:parseTime(input.dayEnd);
 if(start===null||end===null||end<=start)throw Error('Daily availability must end after it starts.');
 const preference={morning:[0,720],afternoon:[720,1020],evening:[1020,1440]}[input.preference];
 new Intl.DateTimeFormat('en',{timeZone:input.timezone||'UTC'}).format(new Date());
 return {start:Math.max(start,preference?.[0]||0),end:Math.min(end,preference?.[1]??1440)};
}
function planningWindows(input,date){
 const bounds=planningAvailability(input);if(!validPlanningDate(date))throw Error('Choose a valid availability date.');
 const weekly=normaliseWeeklyAvailability(input.weeklyAvailability),windows=weekly?weekly[new Date(date+'T12:00:00Z').getUTCDay()]:[{start:input.dayStart,end:input.dayEnd}];
 const result=[];for(const window of windows){const start=Math.max(parseTime(window.start),bounds.start),end=Math.min(parseTime(window.end),bounds.end);if(end<=start)continue;const prior=result.at(-1);if(prior&&prior.end===start)prior.end=end;else result.push({start,end})}return result;
}
const intervalsOverlap=(a,b)=>a.date===b.date&&a.startMin<b.endMin&&b.startMin<a.endMin;
function planningGapMinutes(input){
 const value=input.gapMinutes===undefined?0:input.gapMinutes;
 if(!Number.isInteger(value)||![0,5,10,15].includes(value))throw Error('Choose a session gap of 0, 5, 10, or 15 minutes.');
 return value;
}
function planningDailyLimit(input){
 const value=input.dailyLimitMinutes===undefined?0:input.dailyLimitMinutes;
 if(!Number.isInteger(value)||value!==0&&(value<15||value>1440))throw Error('Choose a daily assignment-work limit of 0 (no limit), or 15-1440 minutes.');return value;
}
function planningDailyLimitText(input){const limit=planningDailyLimit(input);return limit?'Daily assignment-work limit: '+limit+' minutes. Existing dated assignment sessions, including completed and locked work, count; gaps do not.':'Daily assignment-work limit: none.'}
function addPlanningDailyWork(work,date,minutes,start=null){
 if(!validPlanningDate(date)||!Number.isFinite(minutes)||minutes<=0)return;
 const first=start===null?minutes:Math.min(minutes,1440-start);work.set(date,(work.get(date)||0)+first);
 if(start!==null&&minutes>first){const next=shiftPlanningDate(date,1);work.set(next,(work.get(next)||0)+minutes-first)}
}
function planningDailyRemaining(work,date,input){const limit=planningDailyLimit(input);return limit?Math.max(0,limit-(work?.get(date)||0)):Infinity}
function planningDailyWork(state,input,excluded=new Set()){
 const work=new Map();if(!planningDailyLimit(input))return work;
 for(const {task} of planningTasks(state)){
  if(!task.assignmentId||excluded.has(task.id))continue;
  if(task.recurrence?.enabled){
   for(const occurrence of planningOccurrences(task,shiftPlanningDate(input.from,-1),input.to,input.from))if(occurrence.status!=='skipped'){
    const explicit=task.recurrence.exceptions?.[occurrence.occurrenceDate]?.override?.durationMinutes;
    addPlanningDailyWork(work,occurrence.displayDate,Number.isFinite(explicit)&&explicit>0?explicit:taskDurationMinutes(occurrence.task),parseTime(occurrence.startTime));
   }
  }else addPlanningDailyWork(work,task.date,taskDurationMinutes(task),parseTime(task.startTime));
 }
 return work;
}
function planningGapText(input){const gap=planningGapMinutes(input);return gap?'Spacing: '+gap+' minutes before or after neighbouring scheduled commitments. Gaps stay as free time; no break tasks are created.':'Spacing: no added gap.'}
function planningIntervalsConflict(a,b,input,cache=new Map()){
 if(intervalsOverlap(a,b))return true;
 const gap=planningGapMinutes(input);if(!gap||Math.abs(Date.parse(a.date)-Date.parse(b.date))>86400000)return false;
 const stamp=(date,minute)=>{const key=(input.timezone||'UTC')+'/'+date+'/'+minute;if(!cache.has(key))cache.set(key,zonedTaskStart(minute===1440?shiftPlanningDate(date,1):date,formatTime(minute%1440,false),input.timezone||'UTC'));return cache.get(key)};
 const first=stamp(a.date,a.startMin),last=stamp(a.date,a.endMin),otherFirst=stamp(b.date,b.startMin),otherLast=stamp(b.date,b.endMin);
 // An invalid commitment boundary cannot establish a safe elapsed-time gap.
 if([first,last,otherFirst,otherLast].some(value=>value===null))return true;
 return first<otherLast+gap*60000&&otherFirst<last+gap*60000;
}
function planningBlockValid(date,start,duration,timezone){
 const end=start+duration;if(start<0||end>1440||duration<1)return false;
 const first=zonedTaskStart(date,formatTime(start,false),timezone),last=zonedTaskStart(end===1440?shiftPlanningDate(date,1):date,formatTime(end%1440,false),timezone);
 return first!==null&&last!==null&&last-first===duration*60000;
}
function planningOccupancy(state,from,to){
 validatePlanningRange(from,to);const out=[];
 function add(item,date,start,duration){
  if(!validPlanningDate(date)||start===null||!Number.isFinite(duration)||duration<=0||duration>1440)return;
  const first={...item,date,startMin:start,endMin:Math.min(1440,start+duration)};
  if(date>=from&&date<=to)out.push(first);
  if(start+duration>1440){const next=shiftPlanningDate(date,1);if(next>=from&&next<=to)out.push({...item,date:next,startMin:0,endMin:start+duration-1440})}
 }
 for(const {task} of planningTasks(state)){
  const item={id:String(task.id),taskId:task.id,title:String(task.title||'Task'),kind:'task',locked:task.scheduleLocked===true};
  if(task.recurrence?.enabled){
   for(const occurrence of planningOccurrences(task,shiftPlanningDate(from,-1),to,from))if(occurrence.status==='pending'){
    const explicit=task.recurrence.exceptions?.[occurrence.occurrenceDate]?.override?.durationMinutes;
    const duration=Number.isFinite(explicit)&&explicit>0?explicit:taskDurationMinutes(occurrence.task);
    add({...item,id:occurrence.occurrenceId,kind:'occurrence',locked:true},occurrence.displayDate,parseTime(occurrence.startTime),duration);
   }
  }else if(!task.completed)add(item,task.date,parseTime(task.startTime),taskDurationMinutes(task));
 }
 for(let date=from;date<=to;date=shiftPlanningDate(date,1)){
  for(const {event,startMin,endMin} of eventSegmentsForDate(state.scheduleEvents,date,{busyOnly:true})){
   out.push({id:String(event.id),taskId:null,title:String(event.title||'Fixed commitment'),kind:'event',locked:true,date,startMin,endMin});
  }
 }
 return out.sort((a,b)=>a.date.localeCompare(b.date)||a.startMin-b.startMin||String(a.id).localeCompare(String(b.id)));
}
function planningConflicts(state,from,to){
 const items=planningOccupancy(state,from,to),out=[];
 for(let i=0;i<items.length;i++)for(let j=i+1;j<items.length;j++){
  if(items[j].date>items[i].date)break;
  if(intervalsOverlap(items[i],items[j])&&!(items[i].kind===items[j].kind&&items[i].id===items[j].id))out.push({date:items[i].date,a:items[i],b:items[j]});
 }
 return out;
}
function planningPlacementOccupancy(state,input){
 const busy=planningOccupancy(state,input.from,input.to);if(!planningGapMinutes(input))return busy;
 // Boundary neighbours matter for gaps, even when a 31-day placement range
 // cannot be widened. Keep the underlying occupancy range limit unchanged.
 for(const date of [shiftPlanningDate(input.from,-1),shiftPlanningDate(input.to,1)])busy.push(...planningOccupancy(state,date,date));
 return busy;
}
function findPlanningSlot(duration,input,busy,clock,spacingCache=new Map()){
 planningAvailability(input);
 if(!Number.isInteger(duration)||duration<1||duration>=1440)throw Error('Choose a duration from 1 to 1439 minutes.');
 if(!validPlanningDate(clock.date)||parseTime(clock.time)===null)throw Error('Current planning time is unavailable.');
 if(input.dueDate&&!validPlanningDate(input.dueDate))throw Error('Review the task deadline first.');
 const last=input.dueDate&&input.dueDate<input.to?input.dueDate:input.to;
 for(let date=input.from;date<=last;date=shiftPlanningDate(date,1)){
  if(date<clock.date||input.assignmentWork!==false&&duration>planningDailyRemaining(input.dailyWork,date,input))continue;
  for(const available of planningWindows(input,date)){
  const earliest=Math.max(available.start,date===clock.date?parseTime(clock.time)+1:0);
  for(let start=Math.ceil(earliest/5)*5;start+duration<=available.end;start+=5){
   const candidate={date,startMin:start,endMin:start+duration};if(busy.some(item=>planningIntervalsConflict(candidate,item,input,spacingCache)))continue;
   if(!planningBlockValid(date,start,duration,input.timezone||'UTC'))continue;
   return {date,startTime:formatTime(start,false),endTime:formatTime((start+duration)%1440,false)};
  }
  }
 }
 return null;
}

Object.assign(exports,{validatePlanningRange,planningAvailability,planningWindows,intervalsOverlap,planningGapMinutes,planningDailyLimit,planningDailyLimitText,addPlanningDailyWork,planningDailyRemaining,planningDailyWork,planningGapText,planningIntervalsConflict,planningBlockValid,planningOccupancy,planningConflicts,planningPlacementOccupancy,findPlanningSlot});
};
modules["schedule-utils.js"]=function(exports,require){
const {eventSegmentsForDate,eventCommitmentsForRange}=require("schedule-events.js");

function toDateKey(date){
  const y=date.getFullYear();
  const m=String(date.getMonth()+1).padStart(2,'0');
  const d=String(date.getDate()).padStart(2,'0');
  return `${y}-${m}-${d}`;
}

function parseTime(value){
  if(!/^\d{1,2}:\d{2}$/.test(String(value||''))) return null;
  const [h,m]=String(value).split(':').map(Number);
  if(h<0||h>23||m<0||m>59) return null;
  return h*60+m;
}

function formatTime(minutes,hour12=true){
  const safe=Math.max(0,Math.min(1439,Math.round(minutes)));
  const h=Math.floor(safe/60),m=safe%60;
  if(!hour12) return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`;
  const period=h>=12?'PM':'AM';
  const h12=h%12||12;
  return `${h12}:${String(m).padStart(2,'0')} ${period}`;
}

function snapMinutes(minutes,interval=15){
  const safeInterval=Math.max(1,Number(interval)||15);
  return Math.max(0,Math.min(1440,Math.round(Number(minutes||0)/safeInterval)*safeInterval));
}

function blockGeometry(startMin,endMin,hourHeight=56,minHeightPx=22){
  const start=Math.max(0,Math.min(1440,Number(startMin)||0));
  const end=Math.max(start,Math.min(1440,Number(endMin)||start));
  const pxPerMinute=(Number(hourHeight)||56)/60;
  return {
    topPx:start*pxPerMinute,
    heightPx:Math.max(Number(minHeightPx)||0,(end-start)*pxPerMinute)
  };
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

function preserveScheduledDuration(task){
  if(!task)return task;
  const start=parseTime(task.startTime),end=parseTime(task.endTime);
  if(start===null||end===null)return task;
  const duration=(end-start+1440)%1440||1440;
  task.lastScheduledMinutes=Math.max(1,Math.round(duration));
  return task;
}

function localDate(date){ return new Date(date.getFullYear(),date.getMonth(),date.getDate(),12); }
function addDays(date,days){ const d=localDate(date); d.setDate(d.getDate()+days); return d; }

function getVisibleDates(anchor,view){
  const a=localDate(anchor);
  if(view==='day') return [a];
  if(view==='three-day') return [0,1,2].map(i=>addDays(a,i));
  const sunday=addDays(a,-a.getDay());
  return Array.from({length:7},(_,i)=>addDays(sunday,i));
}

function shiftAnchor(anchor,view,direction){
  const step=view==='day'?1:view==='three-day'?3:7;
  return addDays(anchor,step*(direction<0?-1:1));
}

function overlaps(a,b){ return a.startMin < b.endMin && b.startMin < a.endMin; }

function layoutOverlaps(items){
  const sorted=items.map(x=>({...x})).sort((a,b)=>a.startMin-b.startMin||a.endMin-b.endMin);
  const groups=[];
  let group=[]; let groupEnd=-1;
  for(const item of sorted){
    if(group.length && item.startMin>=groupEnd){ groups.push(group); group=[]; groupEnd=-1; }
    group.push(item); groupEnd=Math.max(groupEnd,item.endMin);
  }
  if(group.length) groups.push(group);
  const out=[];
  for(const g of groups){
    const ends=[];
    for(const item of g){
      let col=ends.findIndex(end=>end<=item.startMin);
      if(col<0){ col=ends.length; ends.push(item.endMin); } else ends[col]=item.endMin;
      item.column=col;
    }
    const count=Math.max(1,ends.length);
    for(const item of g) out.push({...item,columnCount:count});
  }
  return out;
}

function findConflicts(taskInterval,fixedIntervals=[]){ return fixedIntervals.filter(x=>overlaps(taskInterval,x)); }

function splitOvernightInterval(item){
  const start=parseTime(item.start),end=parseTime(item.end);
  if(start===null||end===null) return [];
  if(end>start) return [{id:item.id,startMin:start,endMin:end,part:'single'}];
  return [
    {id:item.id,startMin:start,endMin:1440,part:'start'},
    {id:item.id,startMin:0,endMin:end,part:'end'}
  ];
}

function applyScheduledMove(task,dateKey,targetMinutes,interval=15){
  const duration=taskDurationMinutes(task);
  let start=snapMinutes(targetMinutes,interval);
  start=Math.min(start,Math.max(0,1440-duration));
  const end=Math.min(1440,start+duration);
  return {date:dateKey,startTime:formatTime(start,false),endTime:formatTime(end%1440,false)};
}

function applyResize(task,targetEndMinutes,interval=15){
  const start=parseTime(task.startTime);
  if(start===null) return {endTime:task.endTime||null};
  let end=snapMinutes(targetEndMinutes,interval);
  end=Math.max(start+1,Math.min(1440,end));
  return {endTime:formatTime(end%1440,false)};
}

function clearScheduledFields(task){
  task.date=null;
  task.startTime=null;
  task.endTime=null;
  return task;
}

function normalizeTaskMetadata(task){
  if(task.dueDate===undefined)task.dueDate=null;
  if(task.estimatedMinutes===undefined)task.estimatedMinutes=null;
  if(task.lastScheduledMinutes===undefined)task.lastScheduledMinutes=null;
  if(task.priority===undefined)task.priority=null;
  if(task.notes===undefined)task.notes='';
  if(task.reminderMinutes===undefined)task.reminderMinutes=null;
  if(task.scheduleLocked===undefined)task.scheduleLocked=false;
  if(task.schedulingPreference===undefined)task.schedulingPreference=null;
  if(task.color===undefined)task.color=null;
  return task;
}

function scheduleFieldsFromDuration(date,startTime,durationMinutes){
  const dateValue=date||null;
  const start=parseTime(startTime);
  if(start===null)return {date:dateValue,startTime:null,endTime:null};
  const duration=Math.max(1,Number(durationMinutes)||60);
  const end=Math.min(1440,start+duration);
  return {date:dateValue,startTime:formatTime(start,false),endTime:formatTime(end%1440,false)};
}

function validDateKey(value){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(String(value||'')))return false;
  const [y,m,d]=String(value).split('-').map(Number);
  const parsed=new Date(y,m-1,d,12);
  return parsed.getFullYear()===y&&parsed.getMonth()===m-1&&parsed.getDate()===d;
}

function proposalConflictsWithRecurring(date,startMin,endMin,fixedEvents=[]){
  if(!validDateKey(date))return true;
  return eventSegmentsForDate(fixedEvents,date,{busyOnly:true}).some(interval=>overlaps({startMin,endMin},interval));
}

function validateScheduleProposals(raw,tasksById,fixedEvents=[],constraints={}){
  if(!Array.isArray(raw))return [];
  const minimumDate=validDateKey(constraints?.minDate)?constraints.minDate:null;
  const maximumDate=validDateKey(constraints?.maxDate)?constraints.maxDate:null;
  const minimumTime=parseTime(constraints?.minTime);
  const blockedWindows=constraints?.blockedWindows||[];
  if(!Array.isArray(blockedWindows)||blockedWindows.some(window=>!validDateKey(window?.date)||parseTime(window?.startTime)===null||parseTime(window?.endTime)===null||parseTime(window.endTime)<=parseTime(window.startTime)))return [];
  const preliminary=[],seen=new Set();
  for(const item of raw){
    const taskId=String(item?.taskId??'');
    const task=tasksById?.get?.(taskId);
    if(!task||task.scheduleLocked||task.completed||task.archived||seen.has(taskId))continue;
    const date=item?.to?.date,start=item?.to?.startTime,modelEnd=item?.to?.endTime;
    const startMin=parseTime(start),rawEndMin=parseTime(modelEnd),modelEndMin=rawEndMin===0&&startMin>0?1440:rawEndMin;
    if(!validDateKey(date)||startMin===null||modelEndMin===null||modelEndMin-startMin<1)continue;
    const plannedDuration=taskDurationMinutes(task);
    const endMin=startMin+plannedDuration;
    if(endMin>1440)continue;
    if(minimumDate&&date<minimumDate)continue;
    if(maximumDate&&date>maximumDate)continue;
    if(minimumDate&&date===minimumDate&&minimumTime!==null&&startMin<minimumTime)continue;
    if(validDateKey(task.dueDate)&&date>task.dueDate)continue;
    if(proposalConflictsWithRecurring(date,startMin,endMin,fixedEvents))continue;
    if(blockedWindows.some(window=>window.date===date&&overlaps({startMin,endMin},{startMin:parseTime(window.startTime),endMin:parseTime(window.endTime)})))continue;
    seen.add(taskId);
    preliminary.push({
      taskId,
      from:{date:task.date??null,startTime:task.startTime??null,endTime:task.endTime??null},
      to:{date,startTime:formatTime(startMin,false),endTime:formatTime(endMin%1440,false)},
      reason:String(item?.reason||'Fits the available time.').trim().slice(0,500),
      conflictIds:Array.isArray(item?.conflictIds)?item.conflictIds.map(String).slice(0,20):[],
      _interval:{date,startMin,endMin}
    });
  }
  let accepted=preliminary;
  // A rejected move leaves its task in the original slot. Recheck dependent
  // moves until none relies on a slot which has stopped being freed.
  while(accepted.length){
    const proposedById=new Map(accepted.map(p=>[p.taskId,p])),finalIntervals=[];
    for(const [id,task] of tasksById||[]){
      if(task?.completed||task?.archived)continue;
      const proposal=proposedById.get(String(id));
      if(proposal){finalIntervals.push({taskId:String(id),...proposal._interval});continue;}
      if(!validDateKey(task?.date))continue;
      const startMin=parseTime(task?.startTime),rawEnd=parseTime(task?.endTime);
      if(startMin===null)continue;
      const endMin=rawEnd===null?Math.min(1440,startMin+taskDurationMinutes(task)):rawEnd>startMin?rawEnd:1440;
      finalIntervals.push({taskId:String(id),date:task.date,startMin,endMin});
    }
    const next=accepted.filter(proposal=>!finalIntervals.some(other=>other.taskId!==proposal.taskId&&other.date===proposal._interval.date&&overlaps(proposal._interval,other)));
    if(next.length===accepted.length)break;
    accepted=next;
  }
  return accepted.map(proposal=>{delete proposal._interval;return proposal});
}

Object.assign(exports,{toDateKey,parseTime,formatTime,snapMinutes,blockGeometry,taskDurationMinutes,preserveScheduledDuration,addDays,getVisibleDates,shiftAnchor,layoutOverlaps,findConflicts,splitOvernightInterval,applyScheduledMove,applyResize,clearScheduledFields,normalizeTaskMetadata,scheduleFieldsFromDuration,validateScheduleProposals,eventSegmentsForDate,eventCommitmentsForRange});
};
modules["recurrence-utils.js"]=function(exports,require){
const DATE_RE=/^\d{4}-\d{2}-\d{2}$/;
const FREQUENCIES=new Set(['daily','weekly','monthly','yearly']);
const MODES=new Set(['fixed','flexible']);
const END_TYPES=new Set(['never','date','count']);
const MONTHLY_MODES=new Set(['date','weekdayPosition']);
const POSITIONS=new Set(['first','second','third','fourth','last']);

function validDateKey(value){
  if(!DATE_RE.test(String(value||'')))return false;
  const [y,m,d]=String(value).split('-').map(Number),dt=new Date(y,m-1,d,12);
  return dt.getFullYear()===y&&dt.getMonth()===m-1&&dt.getDate()===d;
}
function clampInt(value,min,max,fallback){const n=Math.trunc(Number(value));return Number.isFinite(n)&&n>=min&&n<=max?n:fallback}
function normalizedWeekdays(values=[]){return [...new Set((Array.isArray(values)?values:[]).map(Number).filter(n=>Number.isInteger(n)&&n>=0&&n<=6))].sort((a,b)=>a-b)}
function defaultStart(input,fallbackDate){if(validDateKey(input?.startDate))return input.startDate;if(validDateKey(fallbackDate))return fallbackDate;return null}
function dateFromKey(key){const [y,m,d]=String(key).split('-').map(Number);return new Date(y,m-1,d,12)}
function dateKey(date){return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`}
function addDays(key,days){const d=dateFromKey(key);d.setDate(d.getDate()+days);return dateKey(d)}
function dayDiff(a,b){return Math.round((dateFromKey(b)-dateFromKey(a))/86400000)}
function validCandidate(y,m,d){const dt=new Date(y,m-1,d,12);return dt.getFullYear()===y&&dt.getMonth()===m-1&&dt.getDate()===d?dateKey(dt):null}
function weekdayPositionDate(year,month,weekday,position){
  if(position==='last'){const last=new Date(year,month,0,12),delta=(last.getDay()-weekday+7)%7;last.setDate(last.getDate()-delta);return dateKey(last)}
  const order={first:1,second:2,third:3,fourth:4}[position]||1,first=new Date(year,month-1,1,12),offset=(weekday-first.getDay()+7)%7,day=1+offset+(order-1)*7;
  return validCandidate(year,month,day);
}
function parseMinutes(value){const match=/^(\d{1,2}):(\d{2})$/.exec(String(value||''));if(!match)return null;const h=Number(match[1]),m=Number(match[2]);return h>=0&&h<24&&m>=0&&m<60?h*60+m:null}
function formatMinutes(value){const n=Math.max(0,Math.min(1440,Math.round(value)));return `${String(Math.floor(n/60)%24).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`}
function taskDuration(task){const start=parseMinutes(task?.startTime),end=parseMinutes(task?.endTime);if(start!==null&&end!==null&&end>start)return end-start;const estimate=Math.round(Number(task?.estimatedMinutes));return Number.isFinite(estimate)&&estimate>0?estimate:60}

// Validate supplied edits before legacy read-time normalization can repair them.
function assertRecurrenceInput(input){
 const invalid=field=>{throw Error('Invalid repeat rule: review '+field+'.');};
 if(!input||typeof input!=='object'||Array.isArray(input)||input.enabled!==true)invalid('enabled');
 for(const [field,values] of [['frequency',FREQUENCIES],['mode',MODES],['endType',END_TYPES]])if(input[field]!==undefined&&!values.has(input[field]))invalid(field);
 if(Object.hasOwn(input,'interval')&&input.interval==null)invalid('interval');
 for(const field of ['interval','count'])if(input[field]!=null&&(!Number.isSafeInteger(input[field])||input[field]<1))invalid(field);
 if(input.endType==='count'&&input.count==null)invalid('count');
 for(const field of ['startDate','endDate'])if(input[field]!=null&&(typeof input[field]!=='string'||!validDateKey(input[field])))invalid(field);
 if(input.endType==='date'&&input.endDate==null)invalid('end date');
 if(input.weekdays!==undefined&&(!Array.isArray(input.weekdays)||input.weekdays.some(day=>!Number.isInteger(day)||day<0||day>6)))invalid('weekdays');
 for(const [field,max] of [['monthDay',31],['month',12],['weekday',6]])if(input[field]!=null&&(!Number.isInteger(input[field])||input[field]<(field==='weekday'?0:1)||input[field]>max))invalid(field);
 if(input.monthlyMode!=null&&!MONTHLY_MODES.has(input.monthlyMode))invalid('monthly mode');
 if(input.weekdayPosition!=null&&!POSITIONS.has(input.weekdayPosition))invalid('weekday position');
}

/** @param {import('./planner-contracts.js').RecurrenceInput|{recurrence:import('./planner-contracts.js').RecurrenceInput}} [input] @param {string|null} [fallbackDate] */
function normalizeRecurrence(input={},fallbackDate=null){
  const source=input?.recurrence&&typeof input.recurrence==='object'?input.recurrence:input||{},preset=String(source.preset||'').toLowerCase();
  let frequency=FREQUENCIES.has(source.frequency)?source.frequency:'daily',weekdays=normalizedWeekdays(source.weekdays);
  if(preset==='weekdays'){frequency='weekly';weekdays=[1,2,3,4,5]}
  const startDate=defaultStart(source,fallbackDate),interval=Math.max(1,Math.trunc(Number(source.interval)||1));
  const monthlyMode=frequency==='monthly'&&MONTHLY_MODES.has(source.monthlyMode)?source.monthlyMode:(frequency==='monthly'?'date':null),inferredMonthDay=startDate?Number(startDate.slice(8,10)):1,inferredMonth=startDate?Number(startDate.slice(5,7)):1,endType=END_TYPES.has(source.endType)?source.endType:'never',mode=MODES.has(source.mode)?source.mode:'flexible';
  const rule={enabled:source.enabled===true,frequency,interval,weekdays:frequency==='weekly'?weekdays:[],monthlyMode,monthDay:frequency==='monthly'||frequency==='yearly'?clampInt(source.monthDay,1,31,inferredMonthDay):null,weekdayPosition:frequency==='monthly'&&monthlyMode==='weekdayPosition'&&POSITIONS.has(source.weekdayPosition)?source.weekdayPosition:null,weekday:frequency==='monthly'&&monthlyMode==='weekdayPosition'?clampInt(source.weekday,0,6,startDate?dateFromKey(startDate).getDay():0):null,month:frequency==='yearly'?clampInt(source.month,1,12,inferredMonth):null,startDate,endType,endDate:endType==='date'&&validDateKey(source.endDate)?source.endDate:null,count:endType==='count'?Math.max(1,Math.trunc(Number(source.count)||1)):null,mode,exceptions:source.exceptions&&typeof source.exceptions==='object'&&!Array.isArray(source.exceptions)?structuredClone(source.exceptions):{}};
  if(frequency==='weekly'&&!rule.weekdays.length&&startDate)rule.weekdays=[dateFromKey(startDate).getDay()];
  return rule;
}

function validateRecurrence(rule){
  if(!rule||typeof rule!=='object')return false;if(rule.enabled!==true)return true;if(!FREQUENCIES.has(rule.frequency))return false;if(!Number.isInteger(rule.interval)||rule.interval<1)return false;if(!validDateKey(rule.startDate))return false;if(!MODES.has(rule.mode))return false;if(!END_TYPES.has(rule.endType))return false;
  if(rule.endType==='date'&&(!validDateKey(rule.endDate)||rule.endDate<rule.startDate))return false;if(rule.endType==='count'&&(!Number.isInteger(rule.count)||rule.count<1))return false;
  if(rule.frequency==='weekly'&&(!Array.isArray(rule.weekdays)||!rule.weekdays.length||rule.weekdays.some(day=>!Number.isInteger(day)||day<0||day>6)))return false;
  if(rule.frequency==='monthly'){if(!MONTHLY_MODES.has(rule.monthlyMode))return false;if(rule.monthlyMode==='date'&&(!Number.isInteger(rule.monthDay)||rule.monthDay<1||rule.monthDay>31))return false;if(rule.monthlyMode==='weekdayPosition'&&(!POSITIONS.has(rule.weekdayPosition)||!Number.isInteger(rule.weekday)||rule.weekday<0||rule.weekday>6))return false}
  if(rule.frequency==='yearly'&&(!Number.isInteger(rule.month)||rule.month<1||rule.month>12||!Number.isInteger(rule.monthDay)||rule.monthDay<1||rule.monthDay>31))return false;return true;
}

function occurrenceId(seriesId,occurrenceDate){return `${String(seriesId)}::${String(occurrenceDate)}`}

function candidateStream(rule,hardEnd){
  const out=[];if(!validateRecurrence(rule)||!rule.enabled)return out;const limit=rule.endType==='date'&&rule.endDate<hardEnd?rule.endDate:hardEnd;
  if(rule.frequency==='daily'){for(let key=rule.startDate;key<=limit;key=addDays(key,rule.interval))out.push(key);return out}
  if(rule.frequency==='weekly'){for(let key=rule.startDate;key<=limit;key=addDays(key,1)){const weeks=Math.floor(dayDiff(rule.startDate,key)/7);if(weeks%rule.interval===0&&rule.weekdays.includes(dateFromKey(key).getDay()))out.push(key)}return out}
  if(rule.frequency==='monthly'){
    const start=dateFromKey(rule.startDate);for(let offset=0;;offset+=rule.interval){const absolute=start.getMonth()+offset,year=start.getFullYear()+Math.floor(absolute/12),month=((absolute%12)+12)%12+1,key=rule.monthlyMode==='weekdayPosition'?weekdayPositionDate(year,month,rule.weekday,rule.weekdayPosition):validCandidate(year,month,rule.monthDay),monthFirst=`${year}-${String(month).padStart(2,'0')}-01`;if(monthFirst>limit)break;if(key&&key>=rule.startDate&&key<=limit)out.push(key)}return out;
  }
  if(rule.frequency==='yearly'){const startYear=dateFromKey(rule.startDate).getFullYear();for(let year=startYear;;year+=rule.interval){const key=validCandidate(year,rule.month,rule.monthDay),yearFirst=`${year}-01-01`;if(yearFirst>limit)break;if(key&&key>=rule.startDate&&key<=limit)out.push(key)}}return out;
}

function hasOccurrenceScheduleOverride(exception){return ['date','startTime','endTime','durationMinutes'].some(key=>Object.hasOwn(exception?.override||{},key))}

function preserveOccurrenceOnSeriesEdit(exception){return hasOccurrenceScheduleOverride(exception)||['completed','skipped'].includes(exception?.status)}

function generateOccurrenceDates(input,rangeStart,rangeEnd){const rule=normalizeRecurrence(input);if(!rule.enabled||!validDateKey(rule.startDate)||!validDateKey(rangeStart)||!validDateKey(rangeEnd)||rangeEnd<rangeStart)return [];let dates=candidateStream(rule,rangeEnd);if(rule.endType==='count')dates=dates.slice(0,rule.count);dates=dates.filter(key=>key>=rangeStart&&key<=rangeEnd&&(rule.endType!=='date'||key<=rule.endDate));for(const [key,exception] of Object.entries(rule.exceptions||{}))if(validDateKey(key)&&key>=rangeStart&&key<=rangeEnd&&preserveOccurrenceOnSeriesEdit(exception))dates.push(key);return [...new Set(dates)].sort()}
function nextOccurrenceDate(input,afterDate){const rule=normalizeRecurrence(input);if(!rule.enabled||!validDateKey(rule.startDate)||!validDateKey(afterDate))return null;const maxEnd=rule.endType==='date'?rule.endDate:`${dateFromKey(afterDate).getFullYear()+400}-12-31`,dates=candidateStream(rule,maxEnd),limited=rule.endType==='count'?dates.slice(0,rule.count):dates;return limited.find(key=>key>afterDate)||null}

/** @param {import('./planner-contracts.js').RecurringTask} task @param {string} rangeStart @param {string} rangeEnd @param {{today?:string,includeDeleted?:boolean,includeSkipped?:boolean}} [options] */
function generateTaskOccurrences(task,rangeStart,rangeEnd,options={}){
  const rule=normalizeRecurrence(task,task?.date||rangeStart),today=validDateKey(options.today)?options.today:dateKey(new Date());if(!rule.enabled)return [];
  const logicalDates=generateOccurrenceDates(rule,rangeStart,rangeEnd);
  return logicalDates.map(occurrenceDate=>projectOccurrence(task,rule,occurrenceDate,today));
}

function projectOccurrence(task,rule,occurrenceDate,today){
    const seriesId=String(task?.id??'');
    const exception=rule.exceptions?.[occurrenceDate]&&typeof rule.exceptions[occurrenceDate]==='object'?rule.exceptions[occurrenceDate]:null,override=exception?.override&&typeof exception.override==='object'?exception.override:{},effectiveTask={...task,...override,recurrence:task.recurrence},displayDate=validDateKey(override.date)?override.date:occurrenceDate,status=['completed','skipped','deleted'].includes(exception?.status)?exception.status:'pending',duration=override.durationMinutes?Math.max(1,Math.round(Number(override.durationMinutes))):taskDuration(effectiveTask);
    if(Array.isArray(override.checklist))effectiveTask.checklist=structuredClone(override.checklist);
    else if(Array.isArray(task.checklist))effectiveTask.checklist=task.checklist.map(item=>({...item,completed:false}));
    // Focus belongs to the logical occurrence, never to inherited template data.
    effectiveTask.focusLoggedSeconds=Number.isSafeInteger(exception?.focusLoggedSeconds)&&exception.focusLoggedSeconds>=0?exception.focusLoggedSeconds:0;
    if(Number.isInteger(exception?.remainingMinutes)&&exception.remainingMinutes>=1&&exception.remainingMinutes<=1440)effectiveTask.remainingMinutes=exception.remainingMinutes;else delete effectiveTask.remainingMinutes;
    let startTime=null,endTime=null;
    if(rule.mode==='fixed'){startTime=effectiveTask.startTime||null;endTime=effectiveTask.endTime||null;const start=parseMinutes(startTime);if(start!==null&&(!endTime||parseMinutes(endTime)===null))endTime=formatMinutes(start+duration)}
    else if(Object.prototype.hasOwnProperty.call(override,'startTime')){startTime=override.startTime||null;endTime=override.endTime||null;const start=parseMinutes(startTime);if(start!==null&&(!endTime||parseMinutes(endTime)===null))endTime=formatMinutes(start+duration)}
    return {occurrenceId:occurrenceId(seriesId,occurrenceDate),seriesId,occurrenceDate,displayDate,startTime,endTime,durationMinutes:duration,status,isOverdue:status==='pending'&&displayDate<today,isException:!!exception,mode:rule.mode,task:{...effectiveTask,date:displayDate,startTime,endTime}};
}

// Historical completion keeps its logical identity even when the series rule changes.
function projectStoredOccurrence(task,date,options={}){
  if(!task?.recurrence?.enabled||!validDateKey(date))return null;
  const recurrence={...task.recurrence,exceptions:{[date]:task.recurrence.exceptions?.[date]}};
  return projectOccurrence(task,normalizeRecurrence(recurrence,date),date,options.today||date);
}

function generateTaskOccurrencesThrough(task,rangeEnd,options={}){
  const rule=normalizeRecurrence(task,task?.date||rangeEnd),today=validDateKey(options.today)?options.today:dateKey(new Date());
  if(!rule.enabled||!validDateKey(rule.startDate)||!validDateKey(rangeEnd))return [];
  const byId=new Map();
  for(const item of generateTaskOccurrences(task,rule.startDate,rangeEnd,{today})){
    if((item.status==='pending'||options.includeCompleted&&item.status==='completed')&&item.displayDate<=rangeEnd)byId.set(item.occurrenceId,item);
  }
  for(const [logicalDate,exception] of Object.entries(rule.exceptions||{})){
    if(options.includeCompleted&&exception?.status==='completed'&&validDateKey(logicalDate)&&!byId.has(occurrenceId(task.id,logicalDate))){
      const item=projectOccurrence(task,rule,logicalDate,today);if(item.displayDate<=rangeEnd)byId.set(item.occurrenceId,item);
    }
    if(hasOccurrenceScheduleOverride(exception)&&validDateKey(logicalDate)){
      const item=projectOccurrence(task,rule,logicalDate,today);if((item.status==='pending'||options.includeCompleted&&item.status==='completed')&&item.displayDate<=rangeEnd)byId.set(item.occurrenceId,item);
      continue;
    }
    const movedDate=exception?.override?.date;
    if(!validDateKey(logicalDate)||logicalDate<=rangeEnd||!validDateKey(movedDate)||movedDate>rangeEnd)continue;
    const item=generateTaskOccurrences(task,logicalDate,logicalDate,{today})[0];
    if(item?.status==='pending'&&item.displayDate<=rangeEnd)byId.set(item.occurrenceId,item);
  }
  return [...byId.values()].sort((a,b)=>a.displayDate.localeCompare(b.displayDate)||a.occurrenceDate.localeCompare(b.occurrenceDate));
}

const DAY_LONG=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'],DAY_SHORT=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'],MONTH_SHORT=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function ordinal(value){const n=Number(value),mod100=n%100;if(mod100>=11&&mod100<=13)return `${n}th`;return `${n}${n%10===1?'st':n%10===2?'nd':n%10===3?'rd':'th'}`}
function capital(value){const s=String(value||'');return s?s[0].toUpperCase()+s.slice(1):s}
function formatRecurrenceSummary(input,options={}){
  const rule=normalizeRecurrence(input,options.fallbackDate||input?.date||null);if(!rule.enabled)return 'Does not repeat';let text='';
  if(rule.frequency==='daily')text=rule.interval===1?'Daily':`Every ${rule.interval} days`;
  else if(rule.frequency==='weekly'){if(rule.interval===1&&rule.weekdays.length===1)text=`Every ${DAY_LONG[rule.weekdays[0]]}`;else text=`Every ${rule.interval===1?'week':`${rule.interval} weeks`} on ${rule.weekdays.map(day=>DAY_SHORT[day]).join('/')}`}
  else if(rule.frequency==='monthly'){if(rule.monthlyMode==='weekdayPosition')text=`${capital(rule.weekdayPosition)} ${DAY_LONG[rule.weekday]} monthly`;else text=rule.interval===1?`Monthly on the ${ordinal(rule.monthDay)}`:`Every ${rule.interval} months on the ${ordinal(rule.monthDay)}`}
  else if(rule.frequency==='yearly')text=`${rule.interval===1?'Yearly':`Every ${rule.interval} years`} on ${MONTH_SHORT[(rule.month||1)-1]} ${rule.monthDay}`;
  text+=rule.mode==='fixed'?' · Fixed time':' · Flexible';if(rule.endType==='date')text+=` · Ends ${rule.endDate}`;if(rule.endType==='count')text+=` · ${rule.count} occurrence${rule.count===1?'':'s'}`;return text;
}

function setOccurrenceStatus(task,occurrenceDate,status,timestamp=new Date().toISOString()){
  const next=structuredClone(task),rule=normalizeRecurrence(next,next?.date||occurrenceDate),existing=rule.exceptions?.[occurrenceDate]&&typeof rule.exceptions[occurrenceDate]==='object'?structuredClone(rule.exceptions[occurrenceDate]):{};
  if(status==='pending'&&preserveOccurrenceOnSeriesEdit(existing)&&!generateOccurrenceDates({...rule,exceptions:{}},occurrenceDate,occurrenceDate).length){const old=projectOccurrence(next,rule,occurrenceDate,occurrenceDate);existing.override={...existing.override,date:old.displayDate,startTime:old.startTime,endTime:old.endTime,durationMinutes:old.durationMinutes};}
  existing.status=status;delete existing.completedAt;delete existing.skippedAt;if(status==='completed')existing.completedAt=timestamp;if(status==='skipped')existing.skippedAt=timestamp;
  rule.exceptions={...rule.exceptions,[occurrenceDate]:existing};next.recurrence=rule;return next;
}

function applyOccurrenceOverride(task,occurrenceDate,changes={}){
  const next=structuredClone(task),rule=normalizeRecurrence(next,next?.date||occurrenceDate),existing=rule.exceptions?.[occurrenceDate]&&typeof rule.exceptions[occurrenceDate]==='object'?structuredClone(rule.exceptions[occurrenceDate]):{},override=structuredClone(existing.override||{});
  for(const [key,value] of Object.entries(changes||{})){
    if(value===undefined||key==='recurrence')continue;
    const baseline=key==='date'?occurrenceDate:key==='durationMinutes'?taskDuration(task):task?.[key];
    if(key==='checklist'||JSON.stringify(value)!==JSON.stringify(baseline))override[key]=structuredClone(value);
    else delete override[key];
  }
  // A detached date needs a schedule pin even when form values match the template.
  if(preserveOccurrenceOnSeriesEdit(existing)&&!generateOccurrenceDates({...rule,exceptions:{}},occurrenceDate,occurrenceDate).length&&!hasOccurrenceScheduleOverride({override}))override.date=occurrenceDate;
  if(Object.keys(override).length)existing.override=override;else delete existing.override;
  rule.exceptions={...rule.exceptions,[occurrenceDate]:existing};next.recurrence=rule;return next;
}

function splitRecurringSeries(task,occurrenceDate,edits={},newTaskId,{preserveMoved=false}={}){
  const originalTask=structuredClone(task),baseRule=normalizeRecurrence(originalTask,originalTask?.date||occurrenceDate),historical={};
  for(const [key,value] of Object.entries(baseRule.exceptions||{}))if(key<occurrenceDate||preserveMoved&&preserveOccurrenceOnSeriesEdit(value))historical[key]=structuredClone(value);
  // Keep the original identity's time ledger available to history corrections.
  // The new series starts with fresh occurrences and receives no copied time.
  for(const [key,value] of Object.entries(baseRule.exceptions||{}))if(key>=occurrenceDate&&!historical[key]&&Object.hasOwn(value||{},'focusLoggedSeconds'))historical[key]={focusLoggedSeconds:value.focusLoggedSeconds};
  let cutoff=addDays(occurrenceDate,-1);
  if(baseRule.endType==='date'&&baseRule.endDate<cutoff)cutoff=baseRule.endDate;
  if(baseRule.endType==='count'){const dates=generateOccurrenceDates({...baseRule,exceptions:{}},baseRule.startDate,cutoff);cutoff=dates.at(-1)||addDays(baseRule.startDate,-1)}
  originalTask.recurrence={...baseRule,endType:'date',endDate:cutoff,count:null,exceptions:historical};
  const recurrenceEdits=edits?.recurrence&&typeof edits.recurrence==='object'?edits.recurrence:{},taskEdits={...edits};delete taskEdits.recurrence;
  const retained={};if(preserveMoved)for(const [key,value] of Object.entries(baseRule.exceptions||{}))if(key>=occurrenceDate&&preserveOccurrenceOnSeriesEdit(value))retained[key]={status:'deleted'};
  const newTask={...structuredClone(task),...structuredClone(taskEdits),id:newTaskId,completed:false};
  delete newTask.focusLoggedSeconds;delete newTask.remainingMinutes;
  newTask.recurrence=normalizeRecurrence({...baseRule,...recurrenceEdits,enabled:true,startDate:occurrenceDate,exceptions:retained,endType:recurrenceEdits.endType||baseRule.endType,endDate:recurrenceEdits.endType==='date'?recurrenceEdits.endDate:baseRule.endType==='date'?baseRule.endDate:null,count:recurrenceEdits.endType==='count'?recurrenceEdits.count:baseRule.endType==='count'?baseRule.count:null},occurrenceDate);
  if(preserveMoved&&baseRule.endType==='count'&&newTask.recurrence.endType==='count'&&newTask.recurrence.count===baseRule.count){const before=generateOccurrenceDates({...baseRule,exceptions:{}},baseRule.startDate,addDays(occurrenceDate,-1)).length;if(before>=baseRule.count)return {originalTask,newTask:null};newTask.recurrence.count=baseRule.count-before}
  if(newTask.recurrence.endType==='date'&&newTask.recurrence.endDate&&newTask.recurrence.endDate<occurrenceDate){if(preserveMoved)return {originalTask,newTask:null};newTask.recurrence.endType='never';newTask.recurrence.endDate=null}
  return {originalTask,newTask};
}

Object.assign(exports,{assertRecurrenceInput,normalizeRecurrence,validateRecurrence,occurrenceId,hasOccurrenceScheduleOverride,preserveOccurrenceOnSeriesEdit,generateOccurrenceDates,nextOccurrenceDate,generateTaskOccurrences,projectStoredOccurrence,generateTaskOccurrencesThrough,formatRecurrenceSummary,setOccurrenceStatus,applyOccurrenceOverride,splitRecurringSeries});
};
modules["plan-merge.js"]=function(exports,require){
function stableStringify(value) {
    const canonical = item => Array.isArray(item) ? item.map(canonical)
        : item && typeof item === 'object' ? Object.fromEntries(Object.keys(item).sort().map(key => [key, canonical(item[key])])) : item;
    return JSON.stringify(canonical(value));
}
const equal = (a, b) => stableStringify(a) === stableStringify(b);
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const keyed = list => Array.isArray(list) && list.every(item => object(item) && typeof item.id === 'string' && item.id);

// Apply only changes made since the editor's baseline. Concurrent edits to
// another entity/field survive; competing edits fail rather than lose data.
function mergePlanEdits(base, local, remote) {
    if (equal(local, base)) return structuredClone(remote);
    if (equal(remote, base) || equal(local, remote)) return structuredClone(local);
    if (base !== undefined && (local === undefined || remote === undefined)) {
        throw new Error('This item changed in another window or chat. Reload the planner before retrying.');
    }
    if (keyed(base) && keyed(local) && keyed(remote)) {
        const maps = [base, local, remote].map(list => new Map(list.map(item => [item.id, item])));
        if (maps.some((map, index) => map.size !== [base, local, remote][index].length)) {
            throw new Error('Conflicting duplicate planner IDs.');
        }
        const baseIds = base.map(item => item.id), localIds = local.map(item => item.id);
        const common=baseIds.filter(id=>maps[1].has(id)&&maps[2].has(id)),commonOrder=list=>list.map(item=>item.id).filter(id=>common.includes(id)),oldOrder=stableStringify(common),localOrder=stableStringify(commonOrder(local)),remoteOrder=stableStringify(commonOrder(remote));
        if(localOrder!==oldOrder&&remoteOrder!==oldOrder&&localOrder!==remoteOrder)throw new Error('The order changed in another window or chat.');
        const order = equal(baseIds, localIds) ? remote.map(item => item.id) : localIds;
        const ids = [...new Set([...order, ...remote.map(item => item.id), ...localIds])];
        return ids.map(id => mergePlanEdits(maps[0].get(id), maps[1].get(id), maps[2].get(id))).filter(item => item !== undefined);
    }
    if (object(local) && object(remote) && (base === undefined || object(base))) {
        const keys = new Set([...Object.keys(base || {}), ...Object.keys(local), ...Object.keys(remote)]);
        const merged=Object.fromEntries([...keys].map(key => [key, mergePlanEdits(base?.[key], local[key], remote[key])]).filter(([, value]) => value !== undefined));
        if(Array.isArray(merged.boards)){
            const taskIds=new Set();for(const board of merged.boards)for(const section of board.sections||[])for(const task of section.tasks||[]){
                if(typeof task.id!=='string'||!task.id)continue;
                if(taskIds.has(task.id))throw new Error('Conflicting moves created a duplicate task ID. Review the planner.');taskIds.add(task.id);
            }
        }
        return merged;
    }
    throw new Error('This item changed in another window or chat. Reload the planner before retrying.');
}

function planState(data) {
    const boards = Array.isArray(data.boards) ? data.boards
        : Array.isArray(data.sections) ? [{ id: 'legacy-board', title: 'My Routine', sections: data.sections }] : [];
    return structuredClone({
        boards: boards.map(board => ({ ...board, archived: board.archived ?? false,
            sections: (board.sections || []).map(section => ({ ...section, archived: section.archived ?? false,
                tasks: (section.tasks || []).map(task => ({ ...task, archived: task.archived ?? false }))
            }))
        })),
        dayInsights: data.dayInsights || {}, scheduleEvents: data.scheduleEvents || [], calendarSources: data.calendarSources || []
    });
}

// Keep an uncertain submitted state and later edits as two separate changes.
// Evaluate both against the transaction's actual remote state, so an inverse
// edit still applies if the first request commits after a recovery preflight.
function mergePendingPlanEdits(base,local,remote,attempt){
    if(!attempt)return mergePlanEdits(base,local,remote);
    const submitted=mergePlanEdits(attempt.base,attempt.local,remote);
    return mergePlanEdits(attempt.local,local,submitted);
}

Object.assign(exports,{stableStringify,mergePlanEdits,planState,mergePendingPlanEdits});
};
modules["planning-preferences.js"]=function(exports,require){
const {planningGapMinutes,planningDailyLimit}=require("planning-slots.js");

// Stored beside weeklyAvailability in users/{uid}.settings.planning. Missing
// fields preserve the previous unlimited/back-to-back behavior; no migration.
function normalisePlanningPreferences(value={}){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Review your saved planning defaults in Settings.');
 return {dailyLimitMinutes:planningDailyLimit(value),gapMinutes:planningGapMinutes(value)};
}
function savedPlanningPreferences(userData){return normalisePlanningPreferences(userData?.settings?.planning??{})}
function resolvePlanningPreferences(saved={},explicit={}){
 const defaults=normalisePlanningPreferences(saved);
 return normalisePlanningPreferences({dailyLimitMinutes:explicit.dailyLimitMinutes===undefined?defaults.dailyLimitMinutes:explicit.dailyLimitMinutes,gapMinutes:explicit.gapMinutes===undefined?defaults.gapMinutes:explicit.gapMinutes});
}
function planningPreferencesText(saved,chosen=saved){
 const defaults=normalisePlanningPreferences(saved),actual=resolvePlanningPreferences(defaults,chosen),overrides=[];
 const limit=n=>n?n+' minutes per day':'no daily limit',gap=n=>n?n+'-minute gaps':'no added gap';
 if(actual.dailyLimitMinutes!==defaults.dailyLimitMinutes)overrides.push(limit(actual.dailyLimitMinutes));
 if(actual.gapMinutes!==defaults.gapMinutes)overrides.push(gap(actual.gapMinutes));
 return 'Saved planning defaults: '+limit(defaults.dailyLimitMinutes)+', '+gap(defaults.gapMinutes)+'. '+(overrides.length?'Overrides for this plan: '+overrides.join(', ')+'. ':'')+'Changes here apply only to this plan. Edit defaults in Settings > Planning & Schedule > Planning defaults.';
}

Object.assign(exports,{normalisePlanningPreferences,savedPlanningPreferences,resolvePlanningPreferences,planningPreferencesText});
};
modules["weekly-availability.js"]=function(exports,require){
const {parseTime}=require("schedule-utils.js");

// Sunday is index 0, matching fixed commitments and the profile's local dates.
function normaliseWeeklyAvailability(value){
 if(value==null)return null;
 if(typeof value!=='object'||Object.keys(value).length!==7||!Array.from({length:7},(_,day)=>String(day)).every(day=>Object.hasOwn(value,day)))throw Error('Weekly availability needs all seven days.');
 return Object.fromEntries(Array.from({length:7},(_,index)=>{
  const day=value[index];
  if(!Array.isArray(day)||day.length>4)throw Error('Use up to four work windows per day.');
  const windows=day.map(window=>{
   if(!window||typeof window!=='object'||Object.keys(window).some(key=>!['start','end'].includes(key))||!/^\d{2}:\d{2}$/.test(window.start)||!/^\d{2}:\d{2}$/.test(window.end))throw Error('Enter valid start and end times for each work window.');
   const start=parseTime(window.start),end=parseTime(window.end);
   if(start===null||end===null||end<=start)throw Error('Each work window must end after it starts on the same day. Split overnight hours across two days.');
   return {start:window.start,end:window.end};
  }).sort((a,b)=>a.start.localeCompare(b.start));
  for(let i=1;i<windows.length;i++)if(windows[i].start<windows[i-1].end)throw Error('Work windows must not overlap (day '+(index+1)+').');
  return [index,windows];
 }));
}
function savedWeeklyAvailability(userData){return normaliseWeeklyAvailability(userData?.settings?.planning?.weeklyAvailability)}
function planningDefaults(weeklyAvailability,explicit={}){
 const weekly=normaliseWeeklyAvailability(weeklyAvailability);
 if(weekly!==null&&explicit.dayStart===undefined&&explicit.dayEnd===undefined)return {weeklyAvailability:weekly,availabilitySource:'saved'};
 return {dayStart:explicit.dayStart??'07:00',dayEnd:explicit.dayEnd??'22:00',availabilitySource:'daily'};
}
function assertSavedAvailability(options,userData){
 if(options?.availabilitySource==='saved'&&JSON.stringify(normaliseWeeklyAvailability(options.weeklyAvailability))!==JSON.stringify(savedWeeklyAvailability(userData)))throw Error('Your saved weekly availability changed. Review a new preview.');
}

const AVAILABILITY_DAYS=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
function weeklyAvailabilityText(value){const week=normaliseWeeklyAvailability(value);return week===null?'No saved weekly hours':AVAILABILITY_DAYS.map((day,i)=>day+': '+(week[i].map(window=>window.start+'–'+window.end).join(', ')||'Unavailable')).join('; ')}

Object.assign(exports,{normaliseWeeklyAvailability,savedWeeklyAvailability,planningDefaults,assertSavedAvailability,AVAILABILITY_DAYS,weeklyAvailabilityText});
};
modules["schedule-events.js"]=function(exports,require){
const {eventOccurrencesForDate}=require("event-occurrences.js");
// Project fixed commitments onto one calendar date. A dated event never falls
// back to its weekday, even if legacy metadata still includes a day field.
const validDate=value=>typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value;
const minutes=value=>typeof value==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(value)?Number(value.slice(0,2))*60+Number(value.slice(3)):null;
const priorDate=value=>new Date(Date.parse(value+'T12:00:00Z')-86400000).toISOString().slice(0,10);
function eventSegmentsForDate(events,date,{busyOnly=false}={}){
 if(!validDate(date))return [];
 const day=new Date(date+'T12:00:00Z').getUTCDay(),previous=(day+6)%7,previousDate=priorDate(date),out=[];
 for(const event of events||[]){
  if(!event||event.archived)continue;
  for(const effective of eventOccurrencesForDate(event,date)){
   if(busyOnly&&effective.transparent===true)continue;const start=minutes(effective.start),end=minutes(effective.end);if(start===null||end===null)continue;
   out.push({event:effective,startMin:start,endMin:end>start?end:1440,continued:false});
  }
  for(const effective of eventOccurrencesForDate(event,previousDate)){
   if(busyOnly&&effective.transparent===true)continue;const start=minutes(effective.start),end=minutes(effective.end);if(start!==null&&end!==null&&end<=start&&end>0)out.push({event:effective,startMin:0,endMin:end,continued:true});
  }
 }
 return out;
}

// The AI receives the same occupied segments as the schedule validators.
function eventCommitmentsForRange(events,from,to){
 if(!validDate(from)||!validDate(to)||to<from||(Date.parse(to)-Date.parse(from))/86400000>366)return [];
 const rows=[],clock=n=>String(Math.floor(n/60)%24).padStart(2,'0')+':'+String(n%60).padStart(2,'0');
 for(let date=from;date<=to;date=new Date(Date.parse(date+'T12:00:00Z')+86400000).toISOString().slice(0,10)){
  for(const {event,startMin,endMin,continued}of eventSegmentsForDate(events,date,{busyOnly:true}))rows.push({id:JSON.stringify([String(event.id),event.occurrenceDate||event.date||date,date,continued]),eventId:String(event.id),title:String(event.title||''),date,...(event.occurrenceDate?{occurrenceDate:event.occurrenceDate}:{}),start:clock(startMin),end:clock(endMin),allDay:startMin===0&&endMin===1440,continued,category:event.category||'other',readOnly:event.readOnly===true||!!event.calendarSourceId});
 }return rows;
}

Object.assign(exports,{eventSegmentsForDate,eventCommitmentsForRange});
};
modules["task-reminders.js"]=function(exports,require){
const {eventOccurrencesForDate}=require("event-occurrences.js");
const { generateTaskOccurrences }=require("recurrence-utils.js");

function validReminderMinutes(value) {
    return Number.isInteger(value) && value >= 1 && value <= 10080;
}

// Reuse immutable formatters within this request context; timezone math is unchanged.
const nativeFormatters=new Map();
function localParts(epoch, timeZone) {
    if(!nativeFormatters.has(timeZone))nativeFormatters.set(timeZone,new Intl.DateTimeFormat('en-CA', {
        timeZone, year:'numeric', month:'2-digit', day:'2-digit',
        hour:'2-digit', minute:'2-digit', second:'2-digit', hourCycle:'h23'
    }));
    return Object.fromEntries(nativeFormatters.get(timeZone).formatToParts(new Date(epoch)).filter(part=>part.type!=='literal').map(part=>[part.type,part.value]));
}
function wallEpoch(parts) {
    return Date.UTC(+parts.year,+parts.month-1,+parts.day,+parts.hour,+parts.minute,+parts.second);
}
function zonedTaskStart(date,time,timeZone) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date||'') || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time||'')) return null;
    const wanted=Date.parse(date+'T'+time+':00Z');
    if (!Number.isFinite(wanted) || new Date(wanted).toISOString().slice(0,10)!==date) return null;
    const matches=[];
    // Consider both sides of a timezone transition. Gaps have no match;
    // ambiguous starts consistently use the earlier occurrence.
    for(const delta of [-86400000,0,86400000]){
        const sample=wanted+delta,offset=wallEpoch(localParts(sample,timeZone))-sample;
        const candidate=wanted-offset;
        if(wallEpoch(localParts(candidate,timeZone))===wanted)matches.push(candidate);
    }
    return matches.length?Math.min(...matches):null;
}
function shiftDate(date,days){return new Date(Date.parse(date+'T12:00:00Z')+days*86400000).toISOString().slice(0,10)}

function dueTaskReminders(boards, now=Date.now(), timeZone='UTC') {
    let today;
    try {const p=localParts(now,timeZone);today=p.year+'-'+p.month+'-'+p.day}
    catch {return []}
    const start=shiftDate(today,-8),end=shiftDate(today,8),due=[];
    for(const board of boards||[])for(const section of board.sections||[])for(const task of section.tasks||[]){
        if(board.archived||section.archived||!task?.id||task.archived||task.completed)continue;
        let candidates=[{task,key:task.id}];
        if(task.recurrence?.enabled){
            const occurrences=generateTaskOccurrences(task,start,end,{today});
            for(const [logicalDate,exception] of Object.entries(task.recurrence.exceptions||{})){
                const moved=exception?.override?.date;
                if(moved>=start&&moved<=end&&(logicalDate<start||logicalDate>end)){
                    occurrences.push(...generateTaskOccurrences(task,logicalDate,logicalDate,{today}));
                }
            }
            candidates=occurrences.filter(item=>item.status==='pending').map(item=>({task:item.task,key:item.occurrenceId}));
        }
        for(const item of candidates){
            const effective=item.task;
            if(effective.archived||effective.completed||!validReminderMinutes(effective.reminderMinutes))continue;
            const startsAt=zonedTaskStart(effective.date,effective.startTime,timeZone);
            if(startsAt===null)continue;
            const dueAt=startsAt-effective.reminderMinutes*60000;
            if(dueAt<=now&&now<startsAt){
                const id='task-reminder:'+item.key+':'+startsAt+':'+effective.reminderMinutes;
                if(!due.some(reminder=>reminder.id===id))due.push({id,taskId:task.id,title:String(effective.title||'Task'),date:effective.date,startTime:effective.startTime,minutesBefore:effective.reminderMinutes,dueAt,startsAt});
            }
        }
    }
    return due;
}

function reminderDeliveryStatus(settings={}, permission='unsupported') {
    return { enabled:settings.enabled!==false, browserEnabled:settings.browserPush===true, permission };
}

function dueBedtimeReminders(events,now=Date.now(),timeZone='UTC') {
    let today;
    try{const parts=localParts(now,timeZone);today=parts.year+'-'+parts.month+'-'+parts.day}catch{return []}
    const due=[];
    // Include tomorrow: a bedtime shortly after midnight has a reminder today.
    for(const date of [today,shiftDate(today,1)]){
        const day=new Date(date+'T12:00:00Z').getUTCDay();
        for(const event of (events||[]).flatMap(source=>eventOccurrencesForDate(source,date))){
            if(event?.reminderMinutes!==undefined&&event.reminderMinutes!=='default')continue;
            if(!event?.id||event.archived||event.transparent===true||event.allDay===true||event.category!=='sleep'||(event.date!=null?event.date!==date:event.day!==day))continue;
            const startsAt=zonedTaskStart(date,event.start,timeZone);
            if(startsAt===null)continue;
            const dueAt=startsAt-15*60000,id='bedtime-reminder:'+event.id+':'+(event.occurrenceDate?event.occurrenceDate+':':'')+startsAt+':15';
            if(dueAt<=now&&now<startsAt&&!due.some(item=>item.id===id))due.push({id,eventId:event.id,...(event.occurrenceDate?{occurrenceDate:event.occurrenceDate}:{}),title:String(event.title||'Sleep'),date,startTime:event.start,minutesBefore:15,dueAt,startsAt});
        }
    }
    return due;
}

Object.assign(exports,{validReminderMinutes,zonedTaskStart,dueTaskReminders,reminderDeliveryStatus,dueBedtimeReminders});
};
modules["event-occurrences.js"]=function(exports,require){
// Weekly native event identity is the original date, even after a move.
const validEventDate=value=>typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&value>='1900-01-01'&&value<='2200-12-30'&&Number.isFinite(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value;
const isWeeklyNativeEvent=event=>!!event&&event.date==null&&!event.readOnly&&!event.calendarSourceId&&event.day!==null&&event.day!==''&&Number.isInteger(Number(event.day))&&Number(event.day)>=0&&Number(event.day)<=6;
const withinEventDates=(event,date)=>(event.startDate==null||validEventDate(event.startDate)&&date>=event.startDate)&&(event.endDate==null||validEventDate(event.endDate)&&date<=event.endDate);
// Calendar-day arithmetic keeps the alternating phase stable across DST and
// independent of first/last bounds. The reference itself is an occurrence.
function isEventOccurrenceDate(event,date){
 if(!isWeeklyNativeEvent(event)||!validEventDate(date)||new Date(date+'T12:00:00Z').getUTCDay()!==Number(event.day)||!withinEventDates(event,date))return false;
 const interval=event.intervalWeeks===undefined?1:event.intervalWeeks;
 if(interval===1)return true;
 return interval===2&&validEventDate(event.anchorDate)&&new Date(event.anchorDate+'T12:00:00Z').getUTCDay()===Number(event.day)&&(Date.parse(date+'T12:00:00Z')-Date.parse(event.anchorDate+'T12:00:00Z'))%(14*86400000)===0;
}
function eventOccurrence(event,date,{includeSkipped=false,includeInactive=false}={}){
 if(!isEventOccurrenceDate(includeInactive?{...event,startDate:null,endDate:null}:event,date))return null;
 const exception=Object.hasOwn(event.exceptions||{},date)?event.exceptions[date]:null;
 if(exception?.skipped===true&&!includeSkipped)return null;
 const override=exception?.skipped===true?null:exception?.override;
 const effective={...event,...(override&&validEventDate(override.date)?override:{}),id:event.id,date:override&&validEventDate(override.date)?override.date:date,occurrenceDate:date,recurringEvent:true};
 delete effective.startDate;delete effective.endDate;delete effective.intervalWeeks;delete effective.anchorDate;delete effective.day;delete effective.exceptions;
 if(exception?.skipped===true)effective.skippedOccurrence=true;
 return effective;
}
function eventOccurrencesForDate(event,date){
 if(!event||!validEventDate(date))return [];
 if(!isWeeklyNativeEvent(event))return (event.date!=null?event.date===date:Number(event.day)===new Date(date+'T12:00:00Z').getUTCDay())?[event]:[];
 const originals=new Set([date,...Object.keys(event.exceptions||{})]),out=[];
 for(const original of originals){const effective=eventOccurrence(event,original);if(effective?.date===date)out.push(effective);}
 return out;
}

Object.assign(exports,{validEventDate,isWeeklyNativeEvent,withinEventDates,isEventOccurrenceDate,eventOccurrence,eventOccurrencesForDate});
};

modules['planning-commands.js']=function(exports,require){
const {taskRemainingMinutes}=require('remaining-work.js');
const {capturePlanningUndo}=require('planning-undo.js');
const {normaliseWeeklyAvailability}=require('weekly-availability.js');
const {planningTasks,planningClock,validPlanningDate}=require('planning-model.js');
const {findPlanningSlot,planningAvailability,planningWindows,planningBlockValid,planningPlacementOccupancy,planningIntervalsConflict,planningDailyWork,planningDailyRemaining,addPlanningDailyWork,planningDailyLimitText}=require('planning-slots.js');
const {parseTime,taskDurationMinutes}=require('schedule-utils.js');
const {zonedTaskStart}=require('task-reminders.js');
const {stableStringify}=require('plan-merge.js');
const {orderedSessionGroup,orderedPlacementClock,clockAfterSession,expandOrderedTaskIds,assertAssignmentOrder,validateAssignmentOrderChanges}=require('assignment-order.js');

const allTasks=state=>(state.boards||[]).flatMap(board=>(board.sections||[]).flatMap(section=>section.tasks||[]));
function locate(state,id){const entries=planningTasks(state).filter(entry=>entry.task.id===id);if(entries.length!==1||allTasks(state).filter(task=>task.id===id).length!==1)throw Error('A task is missing, archived, or has duplicate IDs.');return entries[0]}
function eligible(state,id){const entry=locate(state,id),task=entry.task;if(task.completed||task.recurrence?.enabled||task.scheduleLocked)throw Error('Completed, recurring, or locked tasks cannot be moved by this planner.');return entry}
const idValid=id=>typeof id==='string'&&id.length>0&&id.length<=160;
function recurrenceSnapshot(rule){if(!rule?.enabled)return null;return {...rule,exceptions:Object.fromEntries(Object.entries(rule.exceptions||{}).map(([date,value])=>[date,{status:value.status||'pending',override:Object.fromEntries(['date','startTime','endTime','durationMinutes'].filter(key=>value.override?.[key]!==undefined).map(key=>[key,value.override[key]]))}]))}}
// Schedule fills missing legacy locks with false; both mean unlocked.
function planningSignature(state){return stableStringify({tasks:planningTasks(state).map(({board,section,task})=>({board:board.id,section:section.id,...Object.fromEntries(['id','date','startTime','endTime','dueDate','estimatedMinutes','remainingMinutes','lastScheduledMinutes','completed','scheduleLocked','schedulingPreference','assignmentId','sessionIndex','sessionOrder'].map(key=>[key,task[key]??(key==='scheduleLocked'?false:null)])),recurrence:recurrenceSnapshot(task.recurrence)})),events:(state.scheduleEvents||[]).map(event=>Object.fromEntries(['id','day','date','start','end','archived','transparent','allDay','exceptions','startDate','endDate','intervalWeeks','anchorDate'].map(key=>[key,event[key]??null])))})}
const options=input=>({...(input.dailyLimitMinutes!==undefined?{dailyLimitMinutes:input.dailyLimitMinutes}:{}),from:input.from,to:input.to,...(input.dayStart!==undefined?{dayStart:input.dayStart}:{}),...(input.dayEnd!==undefined?{dayEnd:input.dayEnd}:{}),timezone:input.timezone||'UTC',...(input.gapMinutes!==undefined?{gapMinutes:input.gapMinutes}:{}),...(input.weeklyAvailability!=null?{weeklyAvailability:normaliseWeeklyAvailability(input.weeklyAvailability)}:{}),...(input.availabilitySource?{availabilitySource:input.availabilitySource}:{})});
const interval=row=>({date:row.date,startMin:parseTime(row.startTime),endMin:parseTime(row.startTime)+row.minutes});
function effectiveDeadline(state,task){
 const parent=task.assignmentId?planningTasks(state).find(entry=>entry.task.id===task.assignmentId)?.task:null;
 const dates=[task.dueDate,parent?.dueDate].filter(Boolean);if(dates.some(date=>!validPlanningDate(date)))throw Error('Review the task or assignment deadline.');
 return dates.sort()[0]||null;
}
function ensureSessionSource(state,parentId){const entry=eligible(state,parentId);if(entry.task.startTime)throw Error('This assignment is already scheduled. Unscheduled assignments can be split into work sessions.');if(allTasks(state).some(task=>task.assignmentId===parentId))throw Error('This assignment already has work sessions. Manage those tasks instead.');return entry}

function previewSessions(state,input,clock,spacingCache=new Map()){
 if(input.ordered!==undefined&&typeof input.ordered!=='boolean')throw Error('Choose a valid session ordering setting.');
 let placementClock=clock;
 const parent=ensureSessionSource(state,input.taskId).task,total=Number(input.totalMinutes),size=Number(input.sessionMinutes),opts=options(input);planningAvailability(opts);
 if(!Number.isInteger(total)||total<15||total>2400||!Number.isInteger(size)||size<15||size>120)throw Error('Choose 15–2400 total minutes and 15–120 minutes per session.');
 const count=Math.ceil(total/size);if(count>40)throw Error('Use at most 40 work sessions in one assignment plan.');
 const labels=input.labels||[];if(!Array.isArray(labels)||labels.length&&labels.length!==count||labels.some(title=>typeof title!=='string'||!title.trim()||title.trim().length>180))throw Error(`Enter exactly ${count} session titles, or leave titles blank.`);
 const used=new Set(allTasks(state).map(task=>task.id)),busy=planningPlacementOccupancy(state,opts),dailyWork=planningDailyWork(state,opts),rows=[];
 for(let index=0;index<count;index++){
  const minutes=Math.min(size,total-index*size),taskId=input.idFactory?.()||'session-'+globalThis.crypto.randomUUID();
  if(!idValid(taskId)||used.has(taskId))throw Error('Work session IDs must be unique.');used.add(taskId);
  const placement=findPlanningSlot(minutes,{...opts,dailyWork,dueDate:parent.dueDate||null,preference:parent.schedulingPreference},busy,placementClock,spacingCache);
  if(!placement)throw Error('Not enough room to fit every session before the deadline'+(opts.gapMinutes?' with '+opts.gapMinutes+'-minute gaps':'')+'. '+planningDailyLimitText(opts)+' Extend availability or reduce the effort; no sessions were created.');
  const row={taskId,title:labels[index]?.trim()||String(parent.title||'Assignment').slice(0,160)+` · ${index+1}/${count}`,minutes,...placement};rows.push(row);busy.push(interval(row));addPlanningDailyWork(dailyWork,row.date,minutes);
  if(input.ordered)placementClock=clockAfterSession(row,clock);
 }
 return {command:{type:'planning_batch',version:1,mode:'sessions',parentId:parent.id,totalMinutes:total,sessionMinutes:size,ordered:input.ordered===true,options:opts,rows},expected:{signature:planningSignature(state)},rows};
}

function previewCarryover(state,input,clock,spacingCache=new Map()){
 const requested=input.taskIds,opts=options(input);planningAvailability(opts);
 if(!Array.isArray(requested)||!requested.length||requested.length>40||new Set(requested).size!==requested.length)throw Error('Choose between 1 and 40 distinct tasks.');
 requested.forEach(id=>eligible(state,id));const ids=expandOrderedTaskIds(state,requested);if(ids.length>40)throw Error('This order requires more than 40 tasks. Review the assignment in a smaller plan.');
 const sources=ids.map(id=>eligible(state,id)).sort((a,b)=>String(effectiveDeadline(state,a.task)||'9999').localeCompare(String(effectiveDeadline(state,b.task)||'9999'))),selected=new Set(ids),working=structuredClone(state);
 const busy=planningPlacementOccupancy(state,opts).filter(item=>item.kind!=='task'||!selected.has(item.taskId)),rows=[],dailyWork=planningDailyWork(state,opts,selected);
 while(sources.length){
  const ready=sources.findIndex(({task})=>{const group=task.assignmentId?orderedSessionGroup(working,task.assignmentId):null;return !group||!group.sessions.some(prior=>!prior.completed&&prior.sessionIndex<task.sessionIndex&&sources.some(entry=>entry.task.id===prior.id))});
  if(ready<0)throw Error('Review the prerequisite session order.');const {task}=sources.splice(ready,1)[0];
  const minutes=taskRemainingMinutes(task),placement=findPlanningSlot(minutes,{...opts,dailyWork,assignmentWork:!!task.assignmentId,dueDate:effectiveDeadline(state,task),preference:task.schedulingPreference},busy,orderedPlacementClock(working,task,clock),spacingCache);
  if(!placement)throw Error(`No safe time fits before the deadline for “${String(task.title||'Task')}”. Adjust the range or availability. ${planningDailyLimitText(opts)}${opts.gapMinutes?' This check includes '+opts.gapMinutes+'-minute gaps.':''}`);
  const row={taskId:task.id,title:String(task.title||'Task'),minutes,...placement};rows.push(row);busy.push(interval(row));if(task.assignmentId)addPlanningDailyWork(dailyWork,row.date,minutes);
  Object.assign(locate(working,task.id).task,placement);
 }
 assertAssignmentOrder(working,new Set(rows.map(row=>locate(working,row.taskId).task.assignmentId).filter(Boolean)));
 return {command:{type:'planning_batch',version:1,mode:'move',options:opts,rows},expected:{signature:planningSignature(state)},rows,notice:ids.length>requested.length?'Includes '+(ids.length-requested.length)+' later sessions to preserve assignment order.':''};
}

function revisionSources(state,parentId){
 const parent=eligible(state,parentId).task;
 if(parent.assignmentId)throw Error('Choose the parent assignment.');
 const sessions=planningTasks(state).map(entry=>entry.task).filter(task=>task.assignmentId===parentId);
 const pending=sessions.filter(task=>!task.completed).sort((a,b)=>(a.sessionIndex||0)-(b.sessionIndex||0)||String(a.id).localeCompare(String(b.id)));
 for(const task of pending)eligible(state,task.id);
 return {parent,pending,completed:sessions.filter(task=>task.completed)};
}
function previewSessionRevision(state,input,clock,spacingCache=new Map()){
 if(!['number','string'].includes(typeof input.remainingMinutes)||typeof input.remainingMinutes==='string'&&!input.remainingMinutes.trim())throw Error('Enter remaining effort, including 0 only when you intend to archive unfinished sessions.');
 const {parent,pending,completed}=revisionSources(state,input.taskId),total=Number(input.remainingMinutes),size=Number(input.sessionMinutes),opts=options(input);planningAvailability(opts);
 if(input.ordered!==undefined&&typeof input.ordered!=='boolean')throw Error('Choose a valid session ordering setting.');
 const ordered=input.ordered??(parent.sessionOrder==='sequential');let placementClock=clock;
 if(!Number.isInteger(total)||total<0||total>2400||!Number.isInteger(size)||size<15||size>120)throw Error('Choose 0-2400 remaining minutes and 15-120 minutes per session.');
 const count=Math.ceil(total/size);if(count+completed.length>40)throw Error('Keep at most 40 active sessions in one assignment plan.');
 if(!count&&!pending.length)throw Error('There are no unfinished sessions to change.');
 const selected=new Set(pending.map(task=>task.id)),busy=planningPlacementOccupancy(state,opts).filter(item=>item.kind!=='task'||!selected.has(item.taskId)),used=new Set(allTasks(state).map(task=>task.id)),rows=[],dailyWork=planningDailyWork(state,opts,selected);
 for(let index=0;index<count;index++){
  const existing=pending[index],minutes=Math.min(size,total-index*size),taskId=existing?.id||input.idFactory?.()||'session-'+globalThis.crypto.randomUUID();
  if(!idValid(taskId)||!existing&&used.has(taskId))throw Error('Work session IDs must be unique.');used.add(taskId);
  const dueDate=[parent.dueDate,existing?.dueDate].filter(Boolean).sort()[0]||null;
  const placement=findPlanningSlot(minutes,{...opts,dailyWork,dueDate,preference:existing?.schedulingPreference||parent.schedulingPreference},busy,placementClock,spacingCache);
  if(!placement)throw Error('Not enough room to fit the remaining effort before its deadlines. '+planningDailyLimitText(opts)+' No sessions were changed.');
  const row={taskId,title:existing?.title||String(parent.title||'Assignment').slice(0,160)+' · New session '+(index+1),minutes,...placement};rows.push(row);busy.push(interval(row));addPlanningDailyWork(dailyWork,row.date,minutes);
  if(ordered)placementClock=clockAfterSession(row,clock);
 }
 return {command:{type:'planning_batch',version:1,mode:'revise-sessions',parentId:parent.id,totalMinutes:total,sessionMinutes:size,ordered,options:opts,rows,archiveIds:pending.slice(count).map(task=>task.id)},expected:{signature:planningSignature(state)},rows};
}

function applyPlanningCommand(state,command,expected,{now=Date.now()}={}){
 if(command?.ordered!==undefined&&typeof command.ordered!=='boolean')throw Error('Invalid session ordering setting.');
 const revising=command?.mode==='revise-sessions';
 if(command?.type!=='planning_batch'||command.version!==1||!['sessions','move','revise-sessions'].includes(command.mode)||!Array.isArray(command.rows)||!command.rows.length&&!(revising&&command.archiveIds?.length)||command.rows.length>40)throw Error('Invalid planning command.');
 if(typeof expected?.signature!=='string'||expected.signature!==planningSignature(state))throw Error('The schedule, deadline, or task status changed. Refresh this preview before applying it.');
 const opts=command.options||{};planningAvailability(opts);const clock=planningClock(now,opts.timezone||'UTC'),rows=command.rows,ids=rows.map(row=>row.taskId),spacingCache=new Map();
 if(ids.some(id=>!idValid(id))||new Set(ids).size!==ids.length)throw Error('Invalid or duplicate work session IDs.');
 let parent=null;
 let archiveIds=[],existingIds=new Set();
 if(revising){
  const source=revisionSources(state,command.parentId);parent=source.parent;
  const total=command.totalMinutes,size=command.sessionMinutes;archiveIds=command.archiveIds;
  if(!Number.isInteger(total)||total<0||total>2400||!Number.isInteger(size)||size<15||size>120||rows.length!==Math.ceil(total/size)||rows.length+source.completed.length>40||rows.some((row,index)=>row.minutes!==Math.min(size,total-index*size))||!Array.isArray(archiveIds)||archiveIds.length>40||new Set(archiveIds).size!==archiveIds.length)throw Error('Invalid session revision.');
  existingIds=new Set(source.pending.map(task=>task.id));
  if(archiveIds.some(id=>!existingIds.has(id)||ids.includes(id))||[...existingIds].some(id=>!ids.includes(id)&&!archiveIds.includes(id))||ids.some(id=>!existingIds.has(id)&&allTasks(state).some(task=>task.id===id)))throw Error('Invalid session targets. Only this assignment’s unfinished sessions may change.');
 }
 if(command.mode==='sessions'){
  parent=ensureSessionSource(state,command.parentId).task;const {totalMinutes:total,sessionMinutes:size}=command;
  if(!Number.isInteger(total)||total<15||total>2400||!Number.isInteger(size)||size<15||size>120||rows.length!==Math.ceil(total/size)||rows.some((row,index)=>row.minutes!==Math.min(size,total-index*size)))throw Error('Invalid session effort or duration.');
  if(allTasks(state).some(task=>ids.includes(task.id)))throw Error('A session ID already exists. Retry the original operation to reconcile its save.');
 }
 const selected=new Set(revising?[...existingIds]:command.mode==='move'?ids:[]),busy=planningPlacementOccupancy(state,opts).filter(item=>item.kind!=='task'||!selected.has(item.taskId)),dailyWork=planningDailyWork(state,opts,selected);
 for(const row of rows){
  const task=revising&&existingIds.has(row.taskId)?eligible(state,row.taskId).task:parent||eligible(state,row.taskId).task,start=parseTime(row.startTime),end=parseTime(row.endTime),windows=planningWindows({...opts,preference:task.schedulingPreference||parent?.schedulingPreference},row.date);
  if(!Number.isInteger(row.minutes)||row.minutes<1||row.minutes>=1440||start===null||end===null||(end-start+1440)%1440!==row.minutes||start%5!==0||!windows.some(window=>start>=window.start&&start+row.minutes<=window.end)||!validPlanningDate(row.date)||row.date<opts.from||row.date>opts.to)throw Error('Invalid session schedule, time, or duration.');
  if(!parent&&row.minutes!==taskRemainingMinutes(task))throw Error('This task duration changed. Refresh the preview.');
  if(task.dueDate&&(!validPlanningDate(task.dueDate)||row.date>task.dueDate))throw Error('This placement would miss its deadline.');
  const deadline=effectiveDeadline(state,task);if(deadline&&row.date>deadline)throw Error('This placement would miss the task or assignment deadline.');
  if(parent?.dueDate&&(!validPlanningDate(parent.dueDate)||row.date>parent.dueDate))throw Error('This placement would miss the assignment deadline.');
  if(row.date<clock.date||zonedTaskStart(row.date,row.startTime,opts.timezone||'UTC')<now||!planningBlockValid(row.date,start,row.minutes,opts.timezone||'UTC'))throw Error('This preview time is in the past or crosses a timezone transition. Refresh it.');
  if(parent||task.assignmentId){if(row.minutes>planningDailyRemaining(dailyWork,row.date,opts))throw Error('This placement exceeds the daily assignment-work limit. Review a new preview.');addPlanningDailyWork(dailyWork,row.date,row.minutes)}
  const nextInterval=interval(row);if(busy.some(item=>planningIntervalsConflict(item,nextInterval,opts,spacingCache)))throw Error('This proposed time conflicts with another commitment. Refresh the preview.');busy.push(nextInterval);
  if(parent&&(typeof row.title!=='string'||!row.title.trim()||row.title.trim().length>180))throw Error('Use a session title up to 180 characters.');
 }
 const next=structuredClone(state);
 if(parent){
  const destination=locate(next,parent.id).section;
  if(command.ordered!==undefined&&(command.ordered||parent.sessionOrder!==undefined))locate(next,parent.id).task.sessionOrder=command.ordered?'sequential':'independent';
  let sequence=Math.max(0,...allTasks(state).filter(task=>task.assignmentId===parent.id).map(task=>Number(task.sessionIndex)||0));
  for(const row of rows){
   if(revising&&existingIds.has(row.taskId)){Object.assign(locate(next,row.taskId).task,{date:row.date,startTime:row.startTime,endTime:row.endTime,estimatedMinutes:row.minutes,lastScheduledMinutes:row.minutes,...(locate(next,row.taskId).task.remainingMinutes!==undefined?{remainingMinutes:row.minutes}:{})});continue}
   destination.tasks.push({id:row.taskId,title:row.title.trim(),completed:false,archived:false,assignmentId:parent.id,sessionIndex:++sequence,date:row.date,startTime:row.startTime,endTime:row.endTime,dueDate:parent.dueDate||null,estimatedMinutes:row.minutes,lastScheduledMinutes:row.minutes,priority:parent.priority||null,schedulingPreference:parent.schedulingPreference||null,scheduleLocked:false,notes:'',checklist:[]});
  }
  for(const id of archiveIds)locate(next,id).task.archived=true;
 }else for(const row of rows){const task=locate(next,row.taskId).task;Object.assign(task,{date:row.date,startTime:row.startTime,endTime:row.endTime,lastScheduledMinutes:row.minutes})}
 validateAssignmentOrderChanges(state,next);
 const planningUndo=capturePlanningUndo(state,next,command);
 return {next,result:{type:'planning_batch',action:command.mode,taskIds:[...ids,...archiveIds],completedTaskIds:[],affectedCount:rows.length+archiveIds.length,...(planningUndo?{planningUndo}:{planningUndoUnavailable:true})}};
}


Object.assign(exports,{planningSignature,previewSessions,previewCarryover,previewSessionRevision,applyPlanningCommand});
};
modules['planning-undo.js']=function(exports,require){
const {stableStringify}=require('plan-merge.js');
const {planningTasks,validPlanningDate,shiftPlanningDate}=require('planning-model.js');
const {planningOccupancy,intervalsOverlap}=require('planning-slots.js');
const {parseTime,formatTime,taskDurationMinutes}=require('schedule-utils.js');
const {zonedTaskStart}=require('task-reminders.js');
const {validateAssignmentOrderChanges}=require('assignment-order.js');

const FIELDS=['date','startTime','endTime','lastScheduledMinutes','estimatedMinutes','remainingMinutes','archived','sessionOrder'];
const GUARDS=[...FIELDS,'dueDate','assignmentId','sessionIndex','scheduleLocked','schedulingPreference'];
const all=state=>(state.boards||[]).flatMap(board=>(board.sections||[]).flatMap(section=>(section.tasks||[]).map(task=>({board,section,task}))));
const guard=task=>stableStringify({...Object.fromEntries(GUARDS.filter(key=>task[key]!==undefined).map(key=>[key,task[key]])),archived:task.archived===true,recurring:task.recurrence?.enabled===true});
function locate(state,id){const found=all(state).filter(entry=>entry.task.id===id);if(found.length!==1||found[0].board.archived||found[0].section.archived)throw Error('An Undo target is missing, moved, archived or ambiguous.');return found[0]}
const location=entry=>({boardId:entry.board.id,sectionId:entry.section.id});
const members=(state,id)=>planningTasks(state).filter(entry=>entry.task.assignmentId===id).map(entry=>entry.task.id).sort();
const values=task=>({date:task.date||null,startTime:task.startTime||null,endTime:task.endTime||null,minutes:taskDurationMinutes(task),archived:task.archived===true,sessionOrder:task.sessionOrder||null});

// Store only the fields the planner changed. Content/completion never enters
// the inverse, and absence is retained separately from an explicit null.
function capturePlanningUndo(before,after,command){
 try{
  const entries=[],parents=new Set(command.parentId?[command.parentId]:[]),ids=new Set([...command.rows.map(row=>row.taskId),...(command.archiveIds||[])]);
  if(command.parentId)ids.add(command.parentId);
  for(const id of ids){
   const current=locate(after,id),previous=all(before).find(entry=>entry.task.id===id),keys=previous?FIELDS.filter(key=>stableStringify(previous.task[key])!==stableStringify(current.task[key])):[];
   if(current.task.assignmentId)parents.add(current.task.assignmentId);
   if(!previous||keys.length)entries.push({id,...location(current),created:!previous,keys,before:previous?Object.fromEntries(keys.filter(key=>previous.task[key]!==undefined).map(key=>[key,structuredClone(previous.task[key])])):{},guard:guard(current.task)});
  }
  if(!entries.length)return null;
  const families=[...parents].filter(id=>all(after).some(entry=>entry.task.id===id)).map(id=>{const parent=locate(after,id);return {id,...location(parent),guard:guard(parent.task),members:members(after,id)}});
  const record={version:1,timezone:command.options.timezone||'UTC',entries,families};
  return entries.length<=81&&JSON.stringify(record).length<=48000?record:null;
 }catch{return null}
}
function checkEntry(state,entry){
 if(!entry||typeof entry.id!=='string'||typeof entry.guard!=='string')throw Error('Invalid saved planning Undo record.');
 const found=locate(state,entry.id);if(found.board.id!==entry.boardId||found.section.id!==entry.sectionId||guard(found.task)!==entry.guard)throw Error('Scheduling, locks, deadlines or task identity changed after this plan. Undo needs manual review.');return found;
}
function validateRestored(state,task,timezone){
 if(task.archived)return;
 if(!task.date){if(task.startTime)throw Error('The previous task time has no valid date. Review it manually.');return}
 if(!validPlanningDate(task.date))throw Error('The previous date needs manual review.');
 const parent=task.assignmentId?planningTasks(state).find(entry=>entry.task.id===task.assignmentId)?.task:null;
 for(const deadline of [task.dueDate,parent?.dueDate].filter(Boolean))if(!validPlanningDate(deadline)||task.date>deadline)throw Error('The previous placement would miss its current deadline.');
 if(!task.startTime)return;
 const start=parseTime(task.startTime),minutes=taskDurationMinutes(task);if(start===null||minutes>1440)throw Error('The previous time or duration needs manual review.');
 const end=start+minutes,endDate=shiftPlanningDate(task.date,Math.floor(end/1440)),first=zonedTaskStart(task.date,formatTime(start,false),timezone),last=zonedTaskStart(endDate,formatTime(end%1440,false),timezone);
 if(first===null||last===null||last-first!==minutes*60000)throw Error('The previous placement crosses an invalid timezone transition.');
 const parts=[{date:task.date,startMin:start,endMin:Math.min(1440,end)}];if(end>1440)parts.push({date:shiftPlanningDate(task.date,1),startMin:0,endMin:end-1440});
 for(const part of parts)if(planningOccupancy(state,part.date,part.date).some(item=>!(item.kind==='task'&&item.taskId===task.id)&&intervalsOverlap(item,part)))throw Error('The previous time conflicts with a current commitment. Review it manually.');
}
function applyPlanningUndo(state,record){
 if(record?.version!==1||typeof record.timezone!=='string'||!Array.isArray(record.entries)||!record.entries.length||record.entries.length>81||!Array.isArray(record.families)||record.families.length>41||new Set(record.entries.map(entry=>entry?.id)).size!==record.entries.length)throw Error('This saved planning Undo record is unavailable or invalid.');
 new Intl.DateTimeFormat('en',{timeZone:record.timezone});
 for(const family of record.families){checkEntry(state,family);if(stableStringify(members(state,family.id))!==stableStringify(family.members))throw Error('Assignment session membership changed after this plan. Review it manually.');}
 for(const entry of record.entries){const found=checkEntry(state,entry);if(typeof entry.created!=='boolean'||!Array.isArray(entry.keys)||entry.keys.length>FIELDS.length||new Set(entry.keys).size!==entry.keys.length||entry.keys.some(key=>!FIELDS.includes(key))||!entry.before||typeof entry.before!=='object'||Array.isArray(entry.before)||Object.keys(entry.before).some(key=>!entry.keys.includes(key)))throw Error('Invalid scheduling fields in the saved Undo record.');if(entry.created&&found.task.completed)throw Error('A newly created session has since been completed. Review it manually instead of archiving it with Undo.');}
 const next=structuredClone(state),rows=[];
 for(const entry of record.entries){
  const task=locate(next,entry.id).task,from=values(task);
  if(entry.created)task.archived=true;
  else for(const key of entry.keys){if(Object.hasOwn(entry.before,key))task[key]=structuredClone(entry.before[key]);else delete task[key]}
  rows.push({taskId:entry.id,title:String(task.title||'Task'),action:entry.created?'Archive created session':entry.keys.every(key=>key==='sessionOrder')?'Restore assignment ordering':'Restore previous scheduling fields',from,to:values(task)});
 }
 for(const entry of record.entries)if(!entry.created)validateRestored(next,locate(next,entry.id).task,record.timezone);
 validateAssignmentOrderChanges(state,next);
 return {next,result:{type:'planning_undo',taskIds:record.entries.map(entry=>entry.id),completedTaskIds:[],affectedCount:record.entries.length},rows};
}
function planningUndoSource(data,sourceOperationId=null){
 const receipts=Array.isArray(data.aiActionReceipts)?data.aiActionReceipts:[],latest=[...receipts].reverse().find(receipt=>receipt.result?.type==='planning_batch');
 if(!latest||sourceOperationId&&!receipts.some(receipt=>receipt.id===sourceOperationId))throw Error('Planning Undo history is no longer available. Older saved changes cannot be reconstructed safely.');
 if(sourceOperationId&&latest.id!==sourceOperationId)throw Error('A newer planning change exists. Review Undo for the latest change.');
 if(latest.planningUndoUsedBy)throw Error('The last planning change was already undone.');
 if(!latest.result.planningUndo)throw Error('Undo is not available for this saved planning change.');return latest;
}
function planningUndoPreview(data,sourceOperationId=null,timezone){
 const source=planningUndoSource(data,sourceOperationId),record=source.result.planningUndo;
 if(timezone&&record.timezone!==timezone)throw Error('Your timezone changed after this plan. Review the previous placements manually.');
 const checked=applyPlanningUndo(data,record);
 return {command:{type:'planning_undo',sourceOperationId:source.id,options:{timezone:record.timezone}},expected:{sourceOperationId:source.id},rows:checked.rows,notice:'Undo restores only this plan\'s scheduling changes. Newly created sessions go to Archive. Notes, checklists, reminders and completion changes are preserved. Original dates, including past dates, are restored only when the current schedule is safe.'};
}


Object.assign(exports,{capturePlanningUndo,applyPlanningUndo,planningUndoSource,planningUndoPreview});
};
modules['remaining-work.js']=function(exports,require){
const {focusOccurrence}=require('occurrence-focus.js');
const {taskDurationMinutes}=require('schedule-utils.js');
const {stableStringify}=require('plan-merge.js');

function taskRemainingMinutes(task){
 return Number.isInteger(task?.remainingMinutes)&&task.remainingMinutes>=1&&task.remainingMinutes<=1440?task.remainingMinutes:taskDurationMinutes(task);
}

// A check-in must not overwrite an estimate or status edited while it was open.
function remainingWorkSnapshot(task){
 return stableStringify(Object.fromEntries(['remainingMinutes','estimatedMinutes','lastScheduledMinutes','date','startTime','endTime','completed','assignmentId'].map(key=>[key,task[key]??null])));
}

function taskWorkCheckin(state,taskId,occurrenceDate=null){
 const all=(state.boards||[]).flatMap(board=>(board.sections||[]).flatMap(section=>(section.tasks||[]).map(task=>({board,section,task})))),matches=all.filter(e=>e.task.id===taskId),found=matches[0];
 if(occurrenceDate){if(matches.length!==1||found.board.archived||found.section.archived||found.task.archived)return null;const occurrence=focusOccurrence(found.task,occurrenceDate);if(!occurrence||occurrence.status!=='pending')return null;return {title:String(occurrence.task.title||'Task').slice(0,160)+' · '+occurrenceDate,remainingMinutes:taskRemainingMinutes(occurrence.task),workExpected:remainingWorkSnapshot(occurrence.task)}}
 if(matches.length!==1||found.board.archived||found.section.archived||found.task.archived||found.task.completed||found.task.recurrence?.enabled||all.some(e=>e.task.assignmentId===taskId))return null;
 return {title:String(found.task.title||'Task').slice(0,180),remainingMinutes:taskRemainingMinutes(found.task),workExpected:remainingWorkSnapshot(found.task)};
}


Object.assign(exports,{taskRemainingMinutes,remainingWorkSnapshot,taskWorkCheckin});
};
modules['assignment-order.js']=function(exports,require){
const {planningTasks,validPlanningDate}=require('planning-model.js');
const {parseTime,taskDurationMinutes}=require('schedule-utils.js');

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


Object.assign(exports,{orderedSessionGroup,assignmentReadiness,clockAfterSession,orderedPlacementClock,expandOrderedTaskIds,assertAssignmentOrder,validateAssignmentOrderChanges});
};
modules['occurrence-focus.js']=function(exports,require){
const {generateTaskOccurrences,normalizeRecurrence}=require('recurrence-utils.js');
const {stableStringify}=require('plan-merge.js');

function validFocusDate(value){return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value}
function focusRecurrenceSignature(task){const rule=normalizeRecurrence(task,task.date);delete rule.exceptions;return stableStringify(rule)}
function focusOccurrence(task,date){
 if(!task?.recurrence?.enabled||!validFocusDate(date))return null;
 const occurrence=generateTaskOccurrences(task,date,date,{today:date})[0];
 if(!occurrence||['skipped','deleted'].includes(occurrence.status))return null;
 return {...occurrence,task:{...occurrence.task,estimatedMinutes:occurrence.durationMinutes,completed:occurrence.status==='completed'}};
}
function setOccurrenceFocus(task,date,patch){
 const existing=task.recurrence?.exceptions?.[date]||{};
 task.recurrence={...task.recurrence,exceptions:{...task.recurrence?.exceptions,[date]:{...existing,...patch}}};
}


Object.assign(exports,{validFocusDate,focusRecurrenceSignature,focusOccurrence,setOccurrenceFocus});
};

globalThis.kairosPlanningRequest=function(json){
 const r=JSON.parse(json),state=r.state,model=require('schedule-find-time-model.js'),base=require('planning-model.js'),overdue=require('schedule-overdue.js'),change=require('schedule-change-model.js');
 const clock=base.planningClock(r.now??Date.now(),r.timezone);
 if(r.mode==='backlog'){
  const entries=base.planningTasks(state),occurrences=[];
  for(const entry of entries)if(entry.task.recurrence?.enabled){
   const task=entry.task,rule=task.recurrence,from=rule.startDate||task.date||clock.date;
   if(!base.validPlanningDate(from)||from<'1900-01-01'||from>'2200-12-30'||Object.keys(rule.exceptions||{}).length>10000)throw Error('This repeat rule exceeds native limits. Review it on the web.');
   const all=require('recurrence-utils.js').generateTaskOccurrences(task,from,base.shiftPlanningDate(clock.date,30),{today:clock.date}),seen=new Set(all.map(o=>o.occurrenceDate));
   for(const day of Object.keys(rule.exceptions||{}))if(!seen.has(day))all.push(...require('recurrence-utils.js').generateTaskOccurrences(task,day,day,{today:clock.date}));
   for(const o of all)occurrences.push({...o,board:entry.board,section:entry.section});
  }
  return JSON.stringify(overdue.scheduleBacklogItems(entries,occurrences,clock).map(item=>({id:String(item.task.id)+(item.occurrence?'/'+item.occurrence.occurrenceDate:''),target:{taskId:String(item.task.id),...(item.occurrence?{occurrenceDate:item.occurrence.occurrenceDate}:{})},title:String(item.task.title||'Task'),reason:item.overdueReason||null,locked:item.task.scheduleLocked===true})));
 }
 if(r.mode==='preview'){
  const saved=r.settings,options={from:clock.date,to:base.shiftPlanningDate(clock.date,13),timezone:r.timezone,dayStart:'07:00',dayEnd:'22:00',weeklyAvailability:saved.weeklyAvailability??null,gapMinutes:saved.gapMinutes,dailyLimitMinutes:saved.dailyLimitMinutes,recovery:r.recovery===true};
  const entry=model.findTimeTask(state,r.target,{recovery:options.recovery,clock});
  options.preference=entry.task.schedulingPreference||'none';
  const report=model.findTaskTimes(state,r.target,options,clock);
  return JSON.stringify({...report,options});
 }
 if(r.mode==='validate'){
  model.assertFindTimeSettings(r.review.options,r.profile);
  model.assertFindTimePlacement(state,r.target,r.changes,r.review,clock);
  return '{}';
 }
 throw Error('Unsupported planning operation.');
};
globalThis.kairosSessionRequest=function(json){
 const r=JSON.parse(json),model=require('planning-commands.js'),undo=require('planning-undo.js'),clock=require('planning-model.js').planningClock(r.now??Date.now(),r.timezone);
 if(r.mode==='preview'||r.mode==='preview-revision'){
  const ids=[...r.ids],input={...r.input,idFactory:()=>ids.shift()};
  return JSON.stringify(r.mode==='preview-revision'?model.previewSessionRevision(r.state,input,clock):model.previewSessions(r.state,input,clock));
 }
 if(r.mode==='apply'){
  require('schedule-find-time-model.js').assertFindTimeSettings(r.command.options,r.profile);
  return JSON.stringify(model.applyPlanningCommand(r.state,r.command,r.expected,{now:r.now??Date.now()}));
 }
 if(r.mode==='undo')return JSON.stringify(undo.applyPlanningUndo(r.state,r.record));
 throw Error('Unsupported session operation.');
};

})();

