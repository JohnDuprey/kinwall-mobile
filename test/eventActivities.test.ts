import {test} from 'node:test'
import assert from 'node:assert/strict'
import {pickEventActivity} from '../src/eventActivities.ts'
const a={activity:'event:a@',eventId:'a',occurrenceStart:null,title:'Soccer',location:null,showAt:'2030-01-01T15:45:00Z',startsAt:'2030-01-01T16:00:00Z',endsAt:'2030-01-01T17:00:00Z',eventEndsAt:'2030-01-01T17:00:00Z',leadAt:null,prep:false}
test('event countdown follows schedule and stops at end',()=>{
 assert.equal(pickEventActivity([a],Date.parse('2030-01-01T15:30:00Z')),null)
 assert.equal(pickEventActivity([a],Date.parse('2030-01-01T15:50:00Z'))?.stage,'start')
 assert.equal(pickEventActivity([a],Date.parse('2030-01-01T16:30:00Z'))?.stage,'end')
 assert.equal(pickEventActivity([a],Date.parse(a.endsAt)),null)
})
test('stopped occurrences are not displayed and event starts work without travel or medicine preferences',async()=>{
 const {activityPushPreferences,activityPushWanted}=await import('../src/activityPushPreferences.ts')
 assert.equal(pickEventActivity([{...a,muted:true}],Date.parse('2030-01-01T16:30:00Z')),null)
 assert.equal(activityPushWanted(activityPushPreferences(false,null,true,true)),true)
 assert.equal(activityPushWanted(activityPushPreferences(false,null,false,true)),false)
})
