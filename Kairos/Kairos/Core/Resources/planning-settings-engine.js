// Vendored validation from Kairos web weekly-availability.js and planning-slots.js.
(function(){
const parseTime=value=>typeof value==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(value)?Number(value.slice(0,2))*60+Number(value.slice(3)):null;

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

function planningGapMinutes(input){
 const value=input.gapMinutes===undefined?0:input.gapMinutes;
 if(!Number.isInteger(value)||![0,5,10,15].includes(value))throw Error('Choose a session gap of 0, 5, 10, or 15 minutes.');
 return value;
}
function planningDailyLimit(input){
 const value=input.dailyLimitMinutes===undefined?0:input.dailyLimitMinutes;
 if(!Number.isInteger(value)||value!==0&&(value<15||value>1440))throw Error('Choose a daily assignment-work limit of 0 (no limit), or 15-1440 minutes.');return value;
}
globalThis.kairosPlanningSettings=json=>{const value=JSON.parse(json);return JSON.stringify({dailyLimitMinutes:planningDailyLimit(value),gapMinutes:planningGapMinutes(value),weeklyAvailability:normaliseWeeklyAvailability(value.weeklyAvailability)});};
})();
