import { test } from 'node:test'
import assert from 'node:assert/strict'
import { DoseReminderState, parseDoseChange } from '../src/doseReminders.ts'

const dose = { medicationId: 'sample-med', date: '2026-10-21', time: '08:00', action: 'taken' }
const request = (identifier: string, time = '08:00') => ({ identifier, content: { data: { ...dose, time } } })

test('Taken cancels just this dose, including snoozed and delivered copies', () => {
  const state = new DoseReminderState()
  state.change(parseDoseChange(dose)!)
  const requests = [request('rem:med:sample'), request('snz:rem:med:sample'), request('rem:med:other', '20:00'), request('cook:timer')]
  assert.deepEqual(state.stale(requests).map(r => r.identifier), ['rem:med:sample', 'snz:rem:med:sample'])
})

test('a refresh started before Taken cannot requeue the stale dose; unmark allows it again', () => {
  const state = new DoseReminderState()
  const oldPlan = request('rem:med:sample')
  const oldRevision = state.revision
  assert.equal(state.blocks(oldPlan), false)
  state.change(parseDoseChange(dose)!)
  state.reconcile(oldRevision, [oldPlan])
  assert.equal(state.blocks(oldPlan), true)
  state.change(parseDoseChange({ ...dose, action: 'unmark' })!)
  assert.equal(state.blocks(oldPlan), false)
  state.change(parseDoseChange({ ...dose, action: 'skipped' })!)
  assert.equal(state.blocks(oldPlan), true)
  state.clear()
  assert.equal(state.blocks(oldPlan), false)
})

test('an authoritative fresh read can restore a dose unmarked on a different device', () => {
  const state = new DoseReminderState()
  const pending = request('rem:med:sample')
  state.change(parseDoseChange(dose)!)
  state.reconcile(state.revision, [pending])
  assert.equal(state.blocks(pending), false)
})

test('untrusted bridge fields cannot cancel unrelated notifications', () => {
  assert.equal(parseDoseChange({ ...dose, action: 'delete' }), null)
  assert.equal(parseDoseChange({ ...dose, medicationId: '' }), null)
  assert.equal(parseDoseChange({ ...dose, date: {} }), null)
  assert.equal(parseDoseChange(null), null)
})
