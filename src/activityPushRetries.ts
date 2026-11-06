type Job = { send: (current:()=>boolean)=>Promise<void>; current:()=>boolean; attempts:number; due?:number }

/** An activity's update token may be emitted only once. Keep failed registrations alive until
 * they succeed, are superseded, or this sign-in is retired. Never log tokens or health data. */
export class ActivityPushRetries {
 private jobs=new Map<string,Job>()
 private timer:ReturnType<typeof setTimeout>|null=null
 register(key:string,send:Job['send'],current:Job['current']):Promise<void> {
  const job:Job={send,current,attempts:0}
  this.jobs.set(key,job)
  return this.attempt(key,job)
 }
 private async attempt(key:string,job:Job):Promise<void> {
  const current=()=>this.jobs.get(key)===job&&job.current()
  if(!current()){if(this.jobs.get(key)===job)this.jobs.delete(key);return}
  job.due=undefined
  try {
   await job.send(current)
   if(this.jobs.get(key)===job)this.jobs.delete(key)
  } catch {
   if(current())job.due=Date.now()+Math.min(60000,5000*2**Math.min(job.attempts++,4))
   else if(this.jobs.get(key)===job)this.jobs.delete(key)
  }
  this.schedule()
 }
 private schedule() {
  if(this.timer!==null)clearTimeout(this.timer)
  this.timer=null
  const due=[...this.jobs.values()].flatMap(job=>job.due===undefined?[]:[job.due])
  if(!due.length)return
  this.timer=setTimeout(()=>{
   this.timer=null
   for(const [key,job]of this.jobs)if(job.due!==undefined&&job.due<=Date.now())void this.attempt(key,job)
  },Math.max(0,Math.min(...due)-Date.now()))
 }
 clear() {
  this.jobs.clear()
  if(this.timer!==null)clearTimeout(this.timer)
  this.timer=null
 }
}
