// Vendored from MRHWCKRR/Kairos event-occurrences.js and schedule-events.js at a9c443ce43e5da3e62b869df7f80918b3e91d882.
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

function kairosScheduleEvents(json) { const r=JSON.parse(json); return JSON.stringify(eventSegmentsForDate(r.events,r.date).map(s=>({id:JSON.stringify([s.event.id,s.event.occurrenceDate||s.event.date||r.date,s.continued]),eventID:String(s.event.id),title:String(s.event.title||''),category:String(s.event.category||'other'),date:r.date,occurrenceDate:s.event.occurrenceDate||null,startMin:s.startMin,endMin:s.endMin,continued:s.continued,readOnly:s.event.readOnly===true||!!s.event.calendarSourceId,transparent:s.event.transparent===true}))); }
