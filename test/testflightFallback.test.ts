import { test } from 'node:test'
import assert from 'node:assert/strict'
import { orchestrate, createGitHub } from '../scripts/testflight-fallback.mjs'

const sha='a'.repeat(40)
const queued={name:'upload',status:'queued',runner_name:'',steps:[]}
const running={...queued,status:'in_progress',runner_name:'runner',steps:[{status:'in_progress'}]}
function fixture(states:Record<string,any[]>,extra:Record<string,unknown>={}) {
 let time=0
 const calls:any[]=[],indices:Record<string,number>={}
 const state=(id:string)=>states[id][Math.min(indices[id]??0,states[id].length-1)]
 const api={
  run:async(id:string)=>{if(id==='parent')return {created_at:'2030-01-01T00:00:00Z'};return state(id).run},
  jobs:async(id:string)=>state(id).jobs??[],
  annotations:async()=>[{message:'The job was not acquired by Runner of type hosted even after multiple attempts'}],
  resolve:async()=>sha,
  start:async(o:any)=>{calls.push(['start',o.runner,o.sourceSha,o.request]);return o.runner},
  cancel:async(id:string)=>{calls.push(['cancel',id]);states[id]=[{run:{status:'completed',conclusion:'cancelled'},jobs:[queued]}];indices[id]=0;return true},
  ...extra,
 }
 const options={api,parentId:'parent',ref:'main',sourceSha:sha,tag:'',selection:'auto',now:()=>time,
  sleep:async(ms:number)=>{time+=ms;for(const id of Object.keys(states))indices[id]=(indices[id]??0)+1},
  log:()=>{},queueMs:30,cancelMs:30,pollMs:10,runningPollMs:10,cancelled:()=>false}
 return {api,calls,options}
}
const success={run:{status:'completed',conclusion:'success'},jobs:[running]}
test('ARM success never dispatches Intel and pins the same source',async()=>{
 const f=fixture({arm:[{run:{status:'queued'},jobs:[queued]},success]})
 assert.equal(await orchestrate(f.options),'arm')
 assert.deepEqual(f.calls,[['start','arm',sha,'parent-arm']])
})
test('ARM queue timeout confirms cancellation before dispatching Intel',async()=>{
 const f=fixture({arm:[{run:{status:'queued'},jobs:[queued]}],intel:[success]})
 assert.equal(await orchestrate(f.options),'intel')
 assert.deepEqual(f.calls.map(c=>c.slice(0,2)),[['start','arm'],['cancel','arm'],['start','intel']])
 assert.ok(f.calls.filter(c=>c[0]==='start').every(c=>c[2]===sha))
})
test('once ARM starts, the queue deadline cannot interrupt its archive',async()=>{
 const f=fixture({arm:[...Array(8).fill({run:{status:'in_progress'},jobs:[running]}),success]})
 await orchestrate(f.options)
 assert.deepEqual(f.calls.map(c=>c.slice(0,2)),[['start','arm']])
})
test('compile/signing/upload failure is not retried on Intel',async()=>{
 const f=fixture({arm:[{run:{status:'completed',conclusion:'failure'},jobs:[{...running,conclusion:'failure'}]}]})
 await assert.rejects(orchestrate(f.options),/failure/)
 assert.equal(f.calls.filter(c=>c[0]==='start').length,1)
})
test('runner acquisition failure falls back; unrelated cancellation does not',async()=>{
 const failed={run:{status:'completed',conclusion:'failure'},jobs:[{...queued,conclusion:'cancelled',id:1}]}
 const f=fixture({arm:[failed],intel:[success]})
 assert.equal(await orchestrate(f.options),'intel')
 const cancelled=fixture({arm:[failed]},{annotations:async()=>[{message:'Cancelled by the user'}]})
 await assert.rejects(orchestrate(cancelled.options),/failure/)
 assert.equal(cancelled.calls.filter(c=>c[0]==='start').length,1)
})
test('a runner acquired at the timeout boundary is allowed to build',async()=>{
 const f=fixture({arm:[...Array(5).fill({run:{status:'queued'},jobs:[queued]}),success]})
 let reads=0
 f.api.jobs=async()=>++reads>4?[running]:[queued]
 await orchestrate(f.options)
 assert.equal(f.calls.some(c=>c[0]==='cancel'),false)
})
test('unconfirmed cancellation and API errors never dispatch an Intel upload',async()=>{
 const f=fixture({arm:[{run:{status:'queued'},jobs:[queued]}]},{cancel:async()=>true})
 await assert.rejects(orchestrate(f.options),/cancellation/)
 assert.equal(f.calls.filter(c=>c[0]==='start').length,1)
 const error=fixture({arm:[{run:{status:'queued'},jobs:[queued]}]},{jobs:async()=>{throw Error('API unavailable')}})
 await assert.rejects(orchestrate(error.options),/API unavailable/)
 assert.equal(error.calls.filter(c=>c[0]==='start').length,1)
})
test('manual Intel selection skips ARM and an environment approval wait does not trigger fallback',async()=>{
 const f=fixture({intel:[success]})
 await orchestrate({...f.options,selection:'intel'})
 assert.deepEqual(f.calls.map(c=>c.slice(0,2)),[['start','intel']])
 const waiting=fixture({arm:[...Array(6).fill({run:{status:'waiting'},jobs:[]}),success]})
 await orchestrate(waiting.options)
 assert.equal(waiting.calls.some(c=>c[0]==='cancel'),false)
})
test('API client resumes a known child rather than dispatching another upload',async()=>{
 const requests:any[]=[]
 const api=createGitHub({repository:'demo/kinwall',token:'obvious-fake',fetch:async(url:string,init:any)=>{
  requests.push([url,init]);return new Response(JSON.stringify({workflow_runs:[{id:42,display_title:'TestFlight build parent-arm',event:'workflow_dispatch'}]}))
 }})
 assert.equal(await api.start({ref:'main',sourceSha:sha,tag:'',runner:'arm',parentId:'parent',request:'parent-arm',createdAt:'2030-01-01T00:00:00Z'}),42)
 assert.equal(requests.length,1);assert.equal(requests[0][1].method,'GET')
})

test('controller rerun resumes an existing Intel handoff instead of retrying ARM',async()=>{
 const f=fixture({intel:[success]}, {find:async()=>({id:'intel'})})
 assert.equal(await orchestrate(f.options),'intel')
 assert.deepEqual(f.calls.map(c=>c.slice(0,2)),[['start','intel']])
})

test('cancelling the controller cancels its active child without dispatching fallback',async()=>{
 const f=fixture({arm:[{run:{status:'queued'},jobs:[queued]}]})
 let polls=0
 await assert.rejects(orchestrate({...f.options,cancelled:()=>++polls>3}),/cancelled/)
 assert.deepEqual(f.calls.map(c=>c.slice(0,2)),[['start','arm'],['cancel','arm']])
})
test('dispatch supports the run-id response and the older 204 correlation response',async()=>{
 for(const modern of [true,false]){
  const calls:any[]=[];let dispatched=false
  const api=createGitHub({repository:'demo/kinwall',token:'obvious-fake',fetch:async(url:string,init:any)=>{
   calls.push([url,init])
   if(init.method==='POST'){
    dispatched=true
    const body=JSON.parse(init.body)
    assert.deepEqual(body,{ref:'main',inputs:{source_sha:sha,tag:'',runner:'arm',parent_id:'123',request:'123-arm'}})
    return modern?new Response(JSON.stringify({workflow_run_id:45})):new Response(null,{status:204})
   }
   return new Response(JSON.stringify({workflow_runs:dispatched?[{id:45,display_title:'TestFlight build 123-arm',event:'workflow_dispatch'}]:[]}))
  }})
  assert.equal(await api.start({ref:'main',sourceSha:sha,tag:'',runner:'arm',parentId:'123',request:'123-arm',createdAt:'2030-01-01T00:00:00Z'}),45)
  assert.equal(calls.filter(c=>c[1].method==='POST').length,1)
 }
})
test('an ambiguous dispatch error is reported without sending another dispatch',async()=>{
 let posts=0
 const api=createGitHub({repository:'demo/kinwall',token:'obvious-fake',fetch:async(_url:string,init:any)=>{
  if(init.method==='POST'){posts++;throw Error('response lost')}
  return new Response(JSON.stringify({workflow_runs:[]}))
 }})
 await assert.rejects(api.start({ref:'main',sourceSha:sha,tag:'',runner:'arm',parentId:'123',request:'123-arm',createdAt:'2030-01-01T00:00:00Z'}),/response lost/)
 assert.equal(posts,1)
})

test('a just-dispatched run whose jobs 404 reads as no jobs yet',async()=>{
 const api=createGitHub({repository:'demo/kinwall',token:'obvious-fake',fetch:async()=>new Response('',{status:404})})
 assert.deepEqual(await api.jobs('1'),[])
 await assert.rejects(api.run('1'),/returned 404/)
})
