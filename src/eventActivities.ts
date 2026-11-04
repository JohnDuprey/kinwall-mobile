// Keep selection in step with kinwall/server/src/event-activity-plan.ts. The server supplies the schedule.
export type EventActivity = { muted?:boolean; activity:string; eventId:string; occurrenceStart:string|null; title:string; location:string|null; showAt:string; startsAt:string; endsAt:string; eventEndsAt:string; leadAt:string|null; prep:boolean };
export function pickEventActivity(plans:EventActivity[],now:number) {
 const a=plans.filter(p=>!p.muted && Date.parse(p.showAt)<=now && now<Date.parse(p.endsAt))
  .sort((a,b)=>Number(Date.parse(b.startsAt)<=now)-Number(Date.parse(a.startsAt)<=now) || Date.parse(a.startsAt)-Date.parse(b.startsAt) || a.activity.localeCompare(b.activity))[0];
 if (!a) return null;
 const stage=now>=Date.parse(a.startsAt) ? 'end' : a.leadAt && now<Date.parse(a.leadAt) ? a.prep ? 'prep' : 'leave' : 'start';
 return {...a,stage,at:stage==='end' ? a.eventEndsAt : stage==='start' ? a.startsAt : a.leadAt!};
}
