(function(){
const validFocusDate=validDateKey;

function buildToday(state={},today) {
 if(!validFocusDate(today))throw Error('A valid Today date is required.');
 const result={date:today,overdue:[],today:[],unscheduled:[]},counts=new Map();
 for(const b of state.boards||[])for(const s of b.sections||[])for(const t of s.tasks||[])counts.set(t.id,(counts.get(t.id)||0)+1);
 for(const board of state.boards||[])for(const section of board.sections||[])for(const task of section.tasks||[]){
  if(board.archived||section.archived||task.archived||!task.id||counts.get(task.id)!==1)continue;
  const base={id:task.id,taskId:task.id,boardId:board.id,sectionId:section.id,title:String(task.title||'Untitled task'),path:String(board.title||'Board')+' / '+String(section.title||'Section'),kind:'task',canComplete:true};
  if(task.recurrence?.enabled){
   for(const item of generateTaskOccurrencesThrough(task,today,{today})){
    if(item.status!=='pending')continue;
    const row={...base,id:task.id+'::'+item.occurrenceDate,title:String(item.task.title||base.title),occurrenceDate:item.occurrenceDate,date:item.displayDate,start:item.startTime||'',end:item.endTime||'',canComplete:false};
    if(row.date===today)result.today.push(row);else if(row.date<today)result.overdue.push(row);
   }
   continue;
  }
  if(task.completed)continue;
  const scheduled=validFocusDate(task.date)?task.date:null,due=validFocusDate(task.dueDate)?task.dueDate:null;
  const row={...base,date:scheduled,dueDate:due,start:task.startTime||'',end:task.endTime||''};
  if((due&&due<today)||(scheduled&&scheduled<today))result.overdue.push(row);
  else if(scheduled===today||due===today)result.today.push(row);
  else if(!scheduled)result.unscheduled.push(row);
 }
 for(const {event,startMin,endMin,continued} of eventSegmentsForDate(state.scheduleEvents,today)){
  const clock=value=>String(Math.floor(value/60)%24).padStart(2,'0')+':'+String(value%60).padStart(2,'0');
  result.today.push({id:event.id,kind:'event',...(event.occurrenceDate?{occurrenceDate:event.occurrenceDate}:{}),title:String(event.title||'Event'),path:event.calendarSourceId?'Imported calendar':'Schedule',date:today,start:clock(startMin),end:clock(endMin),allDay:event.allDay===true,continued,canComplete:false});
 }
 result.today.sort((a,b)=>(a.start||'99:99').localeCompare(b.start||'99:99')||a.title.localeCompare(b.title));
 result.overdue.sort((a,b)=>(a.dueDate||a.date||'').localeCompare(b.dueDate||b.date||''));
 return result;
}

globalThis.kairosTodayRequest=function(json){
 const r=JSON.parse(json),state=r.state;
 if(!validFocusDate(r.today))throw Error('Invalid Today date');
 for(const b of state.boards||[])for(const s of b.sections||[])for(const t of s.tasks||[]){
  if(b.archived||s.archived||t.archived||!t.recurrence?.enabled)continue;
  assertRecurrenceInput(t.recurrence);const rule=normalizeRecurrence(t,t.date||r.today);
  if(Math.abs(Number(r.today.slice(0,4))-Number(rule.startDate.slice(0,4)))>200||Object.keys(rule.exceptions).length>10000)throw Error('Repeat rule exceeds native Today limits');
 }
 const result=buildToday(state,r.today),eventCounts=new Map();
 for(const event of state.scheduleEvents||[])eventCounts.set(event.id,(eventCounts.get(event.id)||0)+1);
 for(const group of ['overdue','today','unscheduled'])result[group]=result[group].filter(row=>row.kind!=='event'||eventCounts.get(row.id)===1).map(row=>({...row,key:JSON.stringify([row.kind,row.id,row.occurrenceDate||null,row.date||null,row.start||null])}));
 return JSON.stringify(result);
};
})();

