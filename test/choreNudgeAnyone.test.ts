import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readChoreNudgeAnyone, saveChoreNudgeAnyone, choreNudgeAnyoneMessage } from '../src/choreNudgeAnyone.ts'

test('Anyone reminders default off and a saved choice survives a new reader', () => {
  const saved = new Map<string, string>()
  const storage = { getItem: (key: string) => saved.get(key) ?? null, setItem: (key: string, value: string) => { saved.set(key, value) } }
  assert.equal(readChoreNudgeAnyone(storage), false)
  assert.equal(saveChoreNudgeAnyone(storage, true), true)
  assert.equal(readChoreNudgeAnyone({ getItem: storage.getItem }), true)
  saveChoreNudgeAnyone(storage, false)
  assert.equal(readChoreNudgeAnyone(storage), false)
  assert.equal(readChoreNudgeAnyone({ getItem: () => { throw Error('locked') } }), false)
  assert.equal(saveChoreNudgeAnyone({ setItem: () => { throw Error('full') } }, true), false)
})
test('Anyone reminder bridge only accepts an explicit boolean', () => {
  for (const m of [null, {}, { type: 'other', on: true }, { type: 'choreNudgeAnyone', on: 'true' }]) assert.equal(choreNudgeAnyoneMessage(m), null)
  assert.equal(choreNudgeAnyoneMessage({ type: 'choreNudgeAnyone', on: true }), true)
  assert.equal(choreNudgeAnyoneMessage({ type: 'choreNudgeAnyone', on: false }), false)
})
