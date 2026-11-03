import { test } from 'node:test'
import assert from 'node:assert/strict'
import { activityPushPreferences, activityPushWanted } from '../src/activityPushPreferences.ts'
import { retireActivityPush } from '../src/activityPushPreferences.ts'
test('sign-out waits for an in-flight registration before removing server and gateway starts',async()=>{
 let finish!:()=>void
 const events:string[]=[]
 const pending=new Promise<void>(resolve=>{finish=()=>{events.push('registered');resolve()}})
 const retired=retireActivityPush(pending,async()=>{events.push('unregistered')},async()=>{events.push('gateway revoked')})
 await Promise.resolve();assert.deepEqual(events,[])
 finish();await retired
 assert.deepEqual(events,['registered','unregistered','gateway revoked'])
 const failed:string[]=[]
 await retireActivityPush(Promise.reject(new Error('registration failed')),async()=>{failed.push('server');throw new Error('offline')},async()=>{failed.push('gateway')})
 assert.deepEqual(failed,['server','gateway'],'a failed server cleanup still revokes the gateway capability')
})
test('medicine push-to-start remains registered when travel reminders are off',()=>{
 const p=activityPushPreferences(false,{on:true,names:false,kids:false})
 assert.equal(p.medications,true);assert.equal(p.leaveBy,false);assert.equal(activityPushWanted(p),true)
})
test('medicine preferences never infer opt-in or treat strings as booleans',()=>{
 assert.deepEqual(activityPushPreferences(true,undefined),{leaveBy:true,medications:false,medicationNames:false,kidDoses:false})
 assert.equal(activityPushWanted(activityPushPreferences(false,{on:'true',names:true,kids:true})),false)
 assert.deepEqual(activityPushPreferences(false,{on:false,names:true,kids:true}),{leaveBy:false,medications:false,medicationNames:false,kidDoses:false})
})
test('permission loss turns off both background starts; restored permission preserves explicit choices',()=>{
 const input={on:true,names:true,kids:true}
 assert.equal(activityPushWanted(activityPushPreferences(true,input,false)),false)
 assert.deepEqual(activityPushPreferences(false,input,true),{leaveBy:false,medications:true,medicationNames:true,kidDoses:true})
})

test('older servers retain travel registration without enabling medicine delivery; other failures are not masked',async()=>{
 const {registerActivityPush}=await import('../src/activityPushPreferences.ts')
 const calls:unknown[]=[];const token={kind:'start' as const,token:'obvious-fake'}
 const p=activityPushPreferences(false,{on:true})
 await registerActivityPush(token,p,async body=>{calls.push(body);if('preferences' in body)throw {status:400};return {push:true}},e=>(e as {status:number}).status===400)
 assert.equal(calls.length,2);assert.deepEqual(calls[1],token)
 let attempts=0
 await assert.rejects(registerActivityPush(token,p,async()=>{attempts++;throw new Error('temporary failure')},()=>false),/temporary failure/)
 assert.equal(attempts,1)
})
