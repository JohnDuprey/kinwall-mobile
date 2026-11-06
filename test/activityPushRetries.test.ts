import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ActivityPushRetries } from '../src/activityPushRetries.ts'

const turn = () => new Promise<void>(resolve => setImmediate(resolve))

test('a failed activity-token registration retries without a new native token event', async t => {
 t.mock.timers.enable({apis:['setTimeout','Date'],now:0})
 const retries = new ActivityPushRetries()
 t.after(()=>retries.clear())
 let attempts=0
 await retries.register('update:medicine',async()=>{ if(++attempts===1)throw new Error('offline') },()=>true)
 assert.equal(attempts,1)
 t.mock.timers.tick(5000);await turn()
 assert.equal(attempts,2,'the same token must reach the server after the connection recovers')
 t.mock.timers.tick(60000);await turn()
 assert.equal(attempts,2,'successful registrations do not keep retrying')
})

test('a newer token replaces a failed registration for the same activity', async t => {
 t.mock.timers.enable({apis:['setTimeout','Date'],now:0})
 const retries=new ActivityPushRetries(),sent:string[]=[]
 t.after(()=>retries.clear())
 await retries.register('update:medicine',async()=>{sent.push('old');throw new Error('offline')},()=>true)
 await retries.register('update:medicine',async()=>{sent.push('new')},()=>true)
 t.mock.timers.tick(60000);await turn()
 assert.deepEqual(sent,['old','new'])
})

test('sign-out and server changes cancel retries, including registrations already in flight', async t => {
 t.mock.timers.enable({apis:['setTimeout','Date'],now:0})
 const retries=new ActivityPushRetries()
 let fail!:()=>void,attempts=0
 const pending=retries.register('update:medicine',async()=>{attempts++;await new Promise<void>((_,reject)=>{fail=()=>reject(new Error('offline'))})},()=>true)
 retries.clear();fail();await pending
 t.mock.timers.tick(60000);await turn()
 assert.equal(attempts,1)
})

test('stale device credentials are never retried',async t=>{
 t.mock.timers.enable({apis:['setTimeout','Date'],now:0})
 const retries=new ActivityPushRetries()
 t.after(()=>retries.clear())
 let current=true,attempts=0
 await retries.register('update:medicine',async()=>{attempts++;throw new Error('offline')},()=>current)
 current=false;t.mock.timers.tick(5000);await turn()
 assert.equal(attempts,1)
})

test('a late failure cannot replace a newer token retry',async t=>{
 t.mock.timers.enable({apis:['setTimeout','Date'],now:0})
 const retries=new ActivityPushRetries(),sent:string[]=[]
 t.after(()=>retries.clear())
 let failOld!:()=>void,newAttempts=0
 const old=retries.register('update:medicine',async()=>{sent.push('old');await new Promise<void>((_,reject)=>{failOld=()=>reject(new Error('offline'))})},()=>true)
 await retries.register('update:medicine',async()=>{sent.push('new');if(++newAttempts===1)throw new Error('offline')},()=>true)
 failOld();await old
 t.mock.timers.tick(5000);await turn()
 assert.deepEqual(sent,['old','new','new'])
})

test('queued registration checks sign-out again before sending credentials',async()=>{
 const retries=new ActivityPushRetries()
 let resume!:()=>void,sent=false
 const pending=retries.register('update:medicine',async current=>{
  await new Promise<void>(resolve=>{resume=resolve})
  if(current())sent=true
 },()=>true)
 retries.clear();resume();await pending
 assert.equal(sent,false)
})
