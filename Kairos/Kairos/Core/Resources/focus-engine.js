// Shared web focus models from MRHWCKRR/Kairos bab63839209f2120ef2d9559c612c9d6105a6c1a.
if(typeof structuredClone==='undefined')globalThis.structuredClone=v=>JSON.parse(JSON.stringify(v));
const focusModules={};

// recurrence-utils.js
focusModules["recurrence-utils.js"]=(()=>{
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


return {assertRecurrenceInput,normalizeRecurrence,validateRecurrence,occurrenceId,hasOccurrenceScheduleOverride,preserveOccurrenceOnSeriesEdit,generateOccurrenceDates,nextOccurrenceDate,generateTaskOccurrences,projectStoredOccurrence,generateTaskOccurrencesThrough,formatRecurrenceSummary,setOccurrenceStatus,applyOccurrenceOverride,splitRecurringSeries};})();

// schedule-utils.js
focusModules["schedule-utils.js"]=(()=>{
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

return {parseTime,taskDurationMinutes};})();

// plan-merge.js
focusModules["plan-merge.js"]=(()=>{
function stableStringify(value) {
    const canonical = item => Array.isArray(item) ? item.map(canonical)
        : item && typeof item === 'object' ? Object.fromEntries(Object.keys(item).sort().map(key => [key, canonical(item[key])])) : item;
    return JSON.stringify(canonical(value));
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


return {stableStringify,planState};})();

// planning-model.js
focusModules["planning-model.js"]=(()=>{
function planningClock(now=Date.now(),timezone='UTC'){
 const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(now)).filter(part=>part.type!=='literal').map(part=>[part.type,part.value]));
 return {date:`${parts.year}-${parts.month}-${parts.day}`,time:`${parts.hour}:${parts.minute}`};
}

return {planningClock};})();

// occurrence-focus.js
focusModules["occurrence-focus.js"]=(()=>{
const {generateTaskOccurrences,normalizeRecurrence}=focusModules["recurrence-utils.js"];
const {stableStringify}=focusModules["plan-merge.js"];

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


return {validFocusDate,focusRecurrenceSignature,focusOccurrence,setOccurrenceFocus};})();

// remaining-work.js
focusModules["remaining-work.js"]=(()=>{
const {focusOccurrence}=focusModules["occurrence-focus.js"];
const {taskDurationMinutes}=focusModules["schedule-utils.js"];
const {stableStringify}=focusModules["plan-merge.js"];

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


return {taskRemainingMinutes,remainingWorkSnapshot,taskWorkCheckin};})();

// focus-history-model.js
focusModules["focus-history-model.js"]=(()=>{
const {setOccurrenceFocus}=focusModules["occurrence-focus.js"];
const {planState,stableStringify}=focusModules["plan-merge.js"];

const id=v=>typeof v==='string'&&v.length>0&&v.length<=160;
const seconds=v=>Number.isSafeInteger(v)&&v>=0;
function count(v){if(v===undefined)return 0;if(!seconds(v))throw Error('Saved focus totals need review.');return v}
function adjust(v,delta){const next=count(v)+delta;if(!seconds(next))throw Error('Saved focus totals need review.');return next}
const tasks=plan=>(plan?.boards||[]).flatMap(b=>(b.sections||[]).flatMap(s=>s.tasks||[]));
const stale=message=>Object.assign(Error(message),{code:'focus-history-stale'});

// Keep the account document bounded. Evicted sessions become part of the
// uneditable baseline; their time stays in all existing aggregates.
function appendFocusHistory(user,plan,entry,result,day){
 const history=structuredClone(user.focusHistory||{sessions:[],baselineLongest:count(user.focusData?.longestSessionSeconds)});
 const parent=entry.target?.assignmentId?tasks(plan).filter(t=>t.id===entry.target.assignmentId):[];
 history.sessions.push({id:entry.id,planId:entry.planId,endedAt:entry.endedAt,day,seconds:entry.seconds,revision:0,taskId:result.taskId,title:result.task?.title||entry.target?.title||'General focus',assignmentTitle:parent.length===1?String(parent[0].title||'Assignment').slice(0,180):'',attributed:result.attributed,...(entry.source==='manual'?{source:'manual'}:{}),...(entry.target?.occurrenceDate?{occurrenceDate:entry.target.occurrenceDate,occurrenceDisplayDate:result.occurrenceDisplayDate||entry.target.occurrenceDate}:{})});
 while(history.sessions.length>100||history.sessions.length>1&&JSON.stringify(history).length>65536){const old=history.sessions.shift();history.baselineLongest=Math.max(count(history.baselineLongest),old.removed?0:old.seconds)}
 return history;
}


return {appendFocusHistory};})();

// focus-model.js
focusModules["focus-model.js"]=(()=>{
const {focusOccurrence,focusRecurrenceSignature,setOccurrenceFocus,validFocusDate}=focusModules["occurrence-focus.js"];
const {setOccurrenceStatus}=focusModules["recurrence-utils.js"];
const {stableStringify,planState}=focusModules["plan-merge.js"];
const {planningClock}=focusModules["planning-model.js"];
const {appendFocusHistory}=focusModules["focus-history-model.js"];
const {remainingWorkSnapshot,taskWorkCheckin}=focusModules["remaining-work.js"];
const MAX_FOCUS_MS=86400000;
const keys=(value,allowed)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).every(k=>allowed.includes(k));
const id=value=>typeof value==='string'&&value.length>0&&value.length<=160;
const nonnegative=value=>Number.isSafeInteger(value)&&value>=0;
const total=value=>value===undefined?0:nonnegative(value)?value:(()=>{throw Error('Saved focus totals need review.');})();
function add(a,b){const result=total(a)+b;if(!Number.isSafeInteger(result))throw Error('Focus total is too large.');return result}
function validTarget(target){return target===null||keys(target,['taskId','boardId','sectionId','assignmentId','title','occurrenceDate','recurrenceSignature'])&&[target.taskId,target.boardId,target.sectionId].every(id)&&(target.assignmentId===null||id(target.assignmentId))&&typeof target.title==='string'&&target.title.length<=180&&(target.occurrenceDate===undefined&&target.recurrenceSignature===undefined||validFocusDate(target.occurrenceDate)&&typeof target.recurrenceSignature==='string'&&target.recurrenceSignature.length>0&&target.recurrenceSignature.length<=2000)}
function focusElapsedMs(session,now=Date.now()){return Math.min(MAX_FOCUS_MS,Math.max(0,(session?.accumulatedMs||0)+(session?.startedAt!=null?Math.max(0,now-session.startedAt):0)))}
function validFocusSession(s){return s?.version===1&&id(s.id)&&id(s.ownerId)&&(s.planId===null||id(s.planId))&&Number.isFinite(s.createdAt)&&s.createdAt>0&&nonnegative(s.accumulatedMs)&&s.accumulatedMs<=MAX_FOCUS_MS&&(s.startedAt===null||Number.isFinite(s.startedAt))&&Number.isFinite(s.lastSeenAt)&&validTarget(s.target)&&(!s.pending||keys(s.pending,['id','ownerId','planId','createdAt','endedAt','seconds','target','mode','remainingMinutes','workExpected']))}
function recoverFocus(s,now=Date.now()){if(!validFocusSession(s))throw Error('The saved focus timer needs review.');return {...structuredClone(s),accumulatedMs:focusElapsedMs(s,Math.min(now,Math.max(s.startedAt||0,s.lastSeenAt))),startedAt:null,lastSeenAt:now}}
function applyFocusLog(user,plan,entry,{now=Date.now()}={}){
 const manual=entry?.source==='manual';
 if(!keys(entry,['id','ownerId','planId','createdAt','endedAt','seconds','target','mode','remainingMinutes','workExpected','source','workDate'])||!id(entry.id)||!id(entry.ownerId)||(entry.planId!==null&&!id(entry.planId))||!validTarget(entry.target)||!['log','complete'].includes(entry.mode)||!Number.isSafeInteger(entry.seconds)||entry.seconds<1||entry.seconds>86400||!Number.isFinite(entry.createdAt)||entry.createdAt<=0||!Number.isFinite(entry.endedAt)||entry.endedAt<entry.createdAt||entry.endedAt>now+60000||!manual&&entry.seconds*1000>entry.endedAt-entry.createdAt+2000)throw Error('Invalid focus session identity, time or fields.');
 if((Object.hasOwn(entry,'source')||Object.hasOwn(entry,'workDate'))&&(!manual||!validFocusDate(entry.workDate)||entry.mode!=='log'||entry.endedAt!==entry.createdAt||Object.hasOwn(entry,'remainingMinutes')||Object.hasOwn(entry,'workExpected')))throw Object.assign(Error('Invalid manual focus date, fields or outcome.'),{code:'focus-manual-invalid'});
 if((entry.remainingMinutes!==undefined||entry.workExpected!==undefined)&&(!Number.isInteger(entry.remainingMinutes)||entry.remainingMinutes<1||entry.remainingMinutes>1440||typeof entry.workExpected!=='string'||entry.workExpected.length>2000||entry.mode!=='log'))throw Error('Invalid remaining-work check-in.');
 if(plan&&plan.userID!==entry.ownerId)throw Error('This planner belongs to another account.');
 const receipts=Array.isArray(user.focusLogReceipts)?user.focusLogReceipts:[],fingerprint=stableStringify(entry),existing=receipts.find(r=>r.id===entry.id);
 if(existing){if(existing.fingerprint!==fingerprint)throw Error('This focus identity belongs to a different log.');return {userPatch:null,planPatch:null,result:{...structuredClone(existing.result),focusData:structuredClone(user.focusData||{})}}}
 const timezone=user.settings?.profile?.timezone||Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
 if(entry.createdAt<=(user.focusLogReceiptFloor||0))throw Object.assign(Error('This focus retry is too old to reconcile. Check your logged time before discarding this session.'),{code:'focus-log-expired'});
 if(manual&&entry.workDate>planningClock(now,timezone).date)throw Object.assign(Error('Choose a work date that is not in the future.'),{code:'focus-manual-invalid'});
 const next=plan?planState(plan):null,all=(next?.boards||[]).flatMap(board=>(board.sections||[]).flatMap(section=>(section.tasks||[]).map(task=>({board,section,task})))),matches=entry.target?all.filter(e=>e.task.id===entry.target.taskId):[],found=matches[0],target=entry.target;
 const occurrence=target?.occurrenceDate&&matches.length===1?focusOccurrence(found.task,target.occurrenceDate):null;
 const attributed=!!(target&&matches.length===1&&!found.board.archived&&!found.section.archived&&!found.task.archived&&(!target.occurrenceDate?!found.task.recurrence?.enabled:occurrence&&focusRecurrenceSignature(found.task)===target.recurrenceSignature)&&found.board.id===target.boardId&&found.section.id===target.sectionId&&(found.task.assignmentId||null)===target.assignmentId);
 if(manual&&target&&!attributed)throw Object.assign(Error('The selected task or occurrence changed. Choose it again or select General focus.'),{code:'focus-target-unavailable'});
 if(entry.mode==='complete'&&!attributed)throw Object.assign(Error('This task changed or is unavailable. Choose Log time to keep the time without completing it.'),{code:'focus-target-unavailable'});
 if(entry.remainingMinutes!==undefined){if(!attributed|| !taskWorkCheckin(next,target.taskId,target.occurrenceDate)||remainingWorkSnapshot(occurrence?.task||found.task)!==entry.workExpected)throw Object.assign(Error('This task or remaining estimate changed. Review the check-in again, or keep the estimate.'),{code:'focus-target-unavailable'});if(occurrence)setOccurrenceFocus(found.task,target.occurrenceDate,{remainingMinutes:entry.remainingMinutes});else found.task.remainingMinutes=entry.remainingMinutes}
 const completedTaskIds=[];if(attributed){
  if(occurrence){setOccurrenceFocus(found.task,target.occurrenceDate,{focusLoggedSeconds:add(found.task.recurrence.exceptions?.[target.occurrenceDate]?.focusLoggedSeconds,entry.seconds)});if(entry.mode==='complete'&&occurrence.status!=='completed'){Object.assign(found.task,setOccurrenceStatus(found.task,target.occurrenceDate,'completed',new Date(now).toISOString()));completedTaskIds.push(occurrence.occurrenceId)}}
  else{found.task.focusLoggedSeconds=add(found.task.focusLoggedSeconds,entry.seconds);if(entry.mode==='complete'&&!found.task.completed){found.task.completed=true;completedTaskIds.push(found.task.id)}}
 }
 const day=manual?entry.workDate:planningClock(entry.endedAt,timezone).date,old=user.focusData||{},focusData={...structuredClone(old),totalSeconds:add(old.totalSeconds,entry.seconds),longestSessionSeconds:Math.max(total(old.longestSessionSeconds),entry.seconds),dailyFocusLog:{...old.dailyFocusLog,[day]:add(old.dailyFocusLog?.[day],entry.seconds)}};
 const result={type:'focus_log',seconds:entry.seconds,attributed,taskId:attributed?target.taskId:null,completedTaskIds,...(attributed?{...(occurrence?{occurrenceDisplayDate:occurrence.displayDate}:{}),task:{id:occurrence?.occurrenceId||found.task.id,title:String(occurrence?.task.title||found.task.title||'Task').slice(0,180),completed:occurrence?entry.mode==='complete'||occurrence.status==='completed':!!found.task.completed}}:{})};
 const retained=[...receipts,{id:entry.id,createdAt:entry.createdAt,fingerprint,result}],removed=[];while(retained.length>100||retained.length>1&&JSON.stringify(retained).length>65536)removed.push(retained.shift());
 return {userPatch:{focusData,focusHistory:appendFocusHistory(user,next,entry,result,day),focusLogReceipts:retained,focusLogReceiptFloor:Math.max(user.focusLogReceiptFloor||0,...removed.map(r=>r.createdAt))},planPatch:attributed?next:null,result:{...result,focusData}};
}


return {MAX_FOCUS_MS,focusElapsedMs,validFocusSession,recoverFocus,applyFocusLog};})();

// focus-breakdown-model.js
focusModules["focus-breakdown-model.js"]=(()=>{
const {validFocusDate}=focusModules["occurrence-focus.js"];
const {generateTaskOccurrences}=focusModules["recurrence-utils.js"];
const {parseTime,taskDurationMinutes}=focusModules["schedule-utils.js"];
const seconds=task=>Number.isSafeInteger(task?.focusLoggedSeconds)&&task.focusLoggedSeconds>0?task.focusLoggedSeconds:0;
const sum=rows=>rows.reduce((total,row)=>total+row.loggedSeconds,0);
const sumMinutes=(rows,key)=>rows.some(row=>row[key]===null)?null:rows.reduce((total,row)=>total+row[key],0);
function estimate(task){
 if(Number.isFinite(task.estimatedMinutes)&&task.estimatedMinutes>0)return Math.round(task.estimatedMinutes);
 if(parseTime(task.startTime)!==null&&parseTime(task.endTime)!==null||Number.isFinite(task.lastScheduledMinutes)&&task.lastScheduledMinutes>0)return taskDurationMinutes(task);
 return null;
}
function effort(task,archived){
 const estimatedMinutes=archived?null:estimate(task);
 const remainingMinutes=archived?null:task.completed?0:Number.isInteger(task.remainingMinutes)&&task.remainingMinutes>=1&&task.remainingMinutes<=1440?task.remainingMinutes:estimatedMinutes;
 return {estimatedMinutes,remainingMinutes};
}
function comparison(row){return {...row,overEstimateSeconds:row.estimatedMinutes===null?null:Math.max(0,row.loggedSeconds-row.estimatedMinutes*60)}}

// Sum each stored ledger once. Assignment rollups are a separate view, never
// additional contributions to board/planner totals. History retention is irrelevant.
function focusBreakdown(state={}){
 const all=(state.boards||[]).flatMap((board,boardIndex)=>(board.sections||[]).flatMap(section=>(section.tasks||[]).map(task=>({board,boardIndex,section,task}))));
 const counts=new Map();for(const {task}of all)counts.set(task.id,(counts.get(task.id)||0)+1);
 const unique=new Map(all.filter(e=>typeof e.task.id==='string'&&e.task.id&&counts.get(e.task.id)===1).map(e=>[e.task.id,e]));
 const children=new Map();
 for(const e of all){const parent=unique.get(e.task.assignmentId)?.task;if(unique.has(e.task.id)&&parent&&!parent.assignmentId&&!parent.recurrence?.enabled&&!e.task.recurrence?.enabled){if(!children.has(parent.id))children.set(parent.id,[]);children.get(parent.id).push(e.task.id)}}
 const tasks=all.map(({board,boardIndex,section,task},index)=>{
  const archived=!!(board.archived||section.archived||task.archived),openable=unique.has(task.id)&&!archived;
  const base={key:'task-'+index,taskId:task.id,boardKey:String(boardIndex),boardTitle:String(board.title||'Board'),sectionTitle:String(section.title||'Section'),title:String(task.title||'Task'),archived,openable,loggedSeconds:seconds(task),...effort(task,archived),kind:children.has(task.id)?'assignment-direct':children.has(task.assignmentId)?'session':'task'};
  if(children.has(task.id)){base.estimatedMinutes=null;base.remainingMinutes=null}
  if(!task.recurrence?.enabled)return comparison(base);
  const ledger=Object.entries(task.recurrence.exceptions||{}).filter(([date,value])=>validFocusDate(date)&&seconds(value)>0).sort(([a],[b])=>a.localeCompare(b));
  // Expand once per series rather than cloning/regenerating the rule per ledger date.
  const generated=new Map((ledger.length?generateTaskOccurrences(task,ledger[0][0],ledger.at(-1)[0],{today:ledger.at(-1)[0]}):[]).filter(item=>!['skipped','deleted'].includes(item.status)).map(item=>[item.occurrenceDate,item]));
  const occurrences=ledger.map(([date,value])=>{
   const occurrence=generated.get(date),duration=value?.override?.durationMinutes;
   const hasEstimate=occurrence&&(estimate(occurrence.task)!==null||Number.isFinite(duration)&&duration>0);
   const effective=occurrence?{...occurrence.task,estimatedMinutes:hasEstimate?occurrence.durationMinutes:null,completed:occurrence.status==='completed'}:null;
   return comparison({...base,key:base.key+'::'+date,kind:'occurrence',occurrenceDate:date,displayDate:occurrence?.displayDate||date,loggedSeconds:seconds(value),openable:openable&&!!occurrence,...(effective?effort(effective,archived):{estimatedMinutes:null,remainingMinutes:null})});
  });
  return {...base,kind:'series',estimatedMinutes:null,remainingMinutes:null,overEstimateSeconds:null,loggedSeconds:base.loggedSeconds+sum(occurrences),occurrences};
 });
 const byId=new Map(tasks.filter(row=>unique.has(row.taskId)).map(row=>[row.taskId,row]));
 const assignments=[...children].map(([parentId,ids])=>{const parent=byId.get(parentId),rows=ids.map(id=>byId.get(id)),active=rows.filter(row=>!row.archived);return comparison({...parent,key:'assignment-'+parent.key,kind:'assignment',loggedSeconds:parent.loggedSeconds+sum(rows),estimatedMinutes:parent.archived?null:sumMinutes(active,'estimatedMinutes'),remainingMinutes:parent.archived?null:sumMinutes(active,'remainingMinutes'),sessionCount:rows.length})});
 const boards=(state.boards||[]).map((board,index)=>{const rows=tasks.filter(row=>row.boardKey===String(index)),finite=rows.filter(row=>!row.archived&&!['series','assignment-direct'].includes(row.kind));return {key:String(index),title:String(board.title||'Board'),archived:!!board.archived,loggedSeconds:sum(rows),taskCount:rows.length,estimatedMinutes:sumMinutes(finite,'estimatedMinutes'),remainingMinutes:sumMinutes(finite,'remainingMinutes')}});
 return {tasks,assignments,boards,totalSeconds:sum(tasks)};
}


return {focusBreakdown};})();

// task-focus.js
focusModules["task-focus.js"]=(()=>{
const {focusOccurrence,focusRecurrenceSignature}=focusModules["occurrence-focus.js"];
const {taskRemainingMinutes}=focusModules["remaining-work.js"];
const {taskDurationMinutes}=focusModules["schedule-utils.js"];
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const entries=state=>(state.boards||[]).flatMap(board=>(board.sections||[]).flatMap(section=>(section.tasks||[]).map(task=>({board,section,task}))));
const logged=task=>Number.isSafeInteger(task.focusLoggedSeconds)&&task.focusLoggedSeconds>0?task.focusLoggedSeconds:0;
function taskFocusTarget(state,id,occurrenceDate=null){const matches=entries(state).filter(e=>e.task.id===id),e=matches[0];if(matches.length!==1||e.board.archived||e.section.archived||e.task.archived||(!occurrenceDate&&e.task.recurrence?.enabled))return null;const occurrence=occurrenceDate?focusOccurrence(e.task,occurrenceDate):null;if(occurrenceDate&&!occurrence)return null;return {taskId:id,boardId:e.board.id,sectionId:e.section.id,assignmentId:e.task.assignmentId||null,title:(String(occurrence?.task.title||e.task.title||'Task').slice(0,occurrence?160:180)+(occurrence?' · '+occurrenceDate:'')).slice(0,180),...(occurrence?{occurrenceDate,recurrenceSignature:focusRecurrenceSignature(e.task)}:{})}}
function taskFocusSummary(state,id,occurrenceDate=null){const target=taskFocusTarget(state,id,occurrenceDate);if(!target)return null;if(occurrenceDate){const occurrence=focusOccurrence(entries(state).find(e=>e.task.id===id).task,occurrenceDate);return {taskId:id,occurrenceDate,plannedMinutes:occurrence.durationMinutes,loggedSeconds:logged(occurrence.task),remainingMinutes:occurrence.status==='completed'?0:taskRemainingMinutes(occurrence.task),assignment:false}}const all=entries(state),task=all.find(e=>e.task.id===id).task,children=all.filter(e=>e.task.assignmentId===id),active=children.filter(e=>!e.board.archived&&!e.section.archived&&!e.task.archived);return {taskId:id,remainingMinutes:children.length?active.filter(e=>!e.task.completed).reduce((n,e)=>n+taskRemainingMinutes(e.task),0):task.completed?0:taskRemainingMinutes(task),plannedMinutes:children.length?active.reduce((n,e)=>n+taskDurationMinutes(e.task),0):taskDurationMinutes(task),loggedSeconds:logged(task)+children.reduce((n,e)=>n+logged(e.task),0),assignment:children.length>0}}

return {taskFocusTarget,taskFocusSummary};})();

function kairosFocusRequest(json){const r=JSON.parse(json);switch(r.operation){
case 'target':return JSON.stringify({target:focusModules['task-focus.js'].taskFocusTarget(r.plan,r.taskId,r.occurrenceDate||null),summary:focusModules['task-focus.js'].taskFocusSummary(r.plan,r.taskId,r.occurrenceDate||null)});
case 'log':return JSON.stringify(focusModules['focus-model.js'].applyFocusLog(r.user,r.plan,r.entry,{now:r.now}));
case 'breakdown':return JSON.stringify(focusModules['focus-breakdown-model.js'].focusBreakdown(r.plan));
default:throw Error('Unsupported focus request');}}
