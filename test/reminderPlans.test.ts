// node --test test/ (npm test). iPhone: local medicine reminders, the chore nudge and the Focus tag.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { choreNudge, doseReminders, focusTag, localAt, type MedicationDay } from '../src/reminderPlans.ts'

const NOW = Date.parse('2026-09-30T15:00:00Z') // a Wednesday
const day: MedicationDay = {
  today: '2026-09-30',
  medications: [
    { id: 'a', times: [{ wake: true, latest: '10:00' }, '08:00', '20:00'], days: [0, 1, 2, 3, 4, 5, 6], endDate: null, dosesLeft: null },
    { id: 'b', times: ['09:00'], days: [3], endDate: null, dosesLeft: null }, // Wednesdays only
    { id: 'c', times: ['07:00'], days: [0, 1, 2, 3, 4, 5, 6], endDate: '2026-09-30', dosesLeft: null }, // ends today
  ],
  days: [{ date: '2026-09-30', doses: [
    { medicationId: 'a', time: 'wake', dueAt: '2026-09-30T20:00:00Z', status: 'upcoming' },
    { medicationId: 'a', time: '08:00', dueAt: '2026-09-30T12:00:00Z', status: 'taken' },
    { medicationId: 'a', time: '20:00', dueAt: '2026-10-01T00:00:00Z', status: 'upcoming' },
  ] }],
}

test("doseReminders: today's upcoming doses at the server's time, then tomorrow's from the schedule", () => {
  const r = doseReminders(day, NOW)
  assert.deepEqual(r.map((d) => `${d.medicationId} ${d.date} ${d.time}`), ['a 2026-09-30 20:00', 'a 2026-10-01 08:00', 'a 2026-10-01 20:00'])
  assert.equal(r[0]!.at, Date.parse('2026-10-01T00:00:00Z'))
  assert.equal(r[1]!.at, localAt('2026-10-01', '08:00'))
})

test('doseReminders: a finished course and a counted one with none left get nothing', () => {
  const r = doseReminders({ ...day, days: [], medications: [{ ...day.medications[1]!, days: [4], dosesLeft: 0 }] }, NOW)
  assert.deepEqual(r, [])
})

test("choreNudge: a chore waiting for a parent's OK isn't left", () => {
  assert.equal(choreNudge([{ id: 'a', title: 'Dishes', memberId: 'maya', completed: false, pending: true }], 'maya'), null)
})

test("choreNudge: the person's chores left; Done only for a single one without an open checklist", () => {
  const c = (id: string, memberId: string | null, extra = {}) => ({ id, title: id, memberId, completed: false, ...extra })
  assert.equal(choreNudge([c('dishes', 'maya'), c('trash', null)], 'sam'), null)
  assert.deepEqual(choreNudge([c('dishes', 'sam'), c('bed', 'sam', { completed: true })], 'sam'), { title: '1 chore left today', body: 'dishes', choreId: 'dishes' })
  assert.equal(choreNudge([c('room', 'sam', { checklist: { total: 3, done: 1 } })], 'sam')?.choreId, null)
  assert.deepEqual(choreNudge([c('a', 'sam'), c('b', 'sam'), c('c', 'sam'), c('d', 'sam')], 'sam'), { title: '4 chores left today', body: 'a, b, c', choreId: null })
})

test("focusTag: only someone else's event is tagged", () => {
  assert.equal(focusTag(['maya'], 'sam'), 'others')
  assert.equal(focusTag(['maya', 'sam'], 'sam'), undefined)
  assert.equal(focusTag([], 'sam'), undefined)
  assert.equal(focusTag(['maya'], null), undefined)
})
