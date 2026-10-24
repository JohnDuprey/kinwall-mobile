import { test } from 'node:test'
import assert from 'node:assert/strict'
import { routineDecision, routineRequest } from '../src/routineMode.ts'
const now = Date.parse('2026-10-22T20:00:00Z')
const state = { enabled: true, locked: false, validUntil: '2026-10-22T23:30:00Z', checkedAt: '2026-10-22T20:00:00Z' }
test('routine grants must be fresh and end before the server cutoff', () => {
  assert.equal(routineDecision(state, now)?.locked, false)
  assert.equal(routineDecision({ ...state, checkedAt: '2026-10-23T00:00:00Z' }, now + 4 * 3600000)?.locked, true)
  assert.equal(routineDecision({ ...state, validUntil: 'bad' }, now), null)
  assert.equal(routineDecision({ ...state, locked: 'false' }, now), null)
  assert.equal(routineDecision({ ...state, checkedAt: '2027-01-01T00:00:00Z' }, now), null)
})
test('routine bridge accepts only known actions and member identifiers', () => {
  assert.deepEqual(routineRequest({ action: 'setup', memberId: 'maya' }), { action: 'setup', memberId: 'maya' })
  assert.deepEqual(routineRequest({ action: 'chooseApps', memberId: 'maya' }), { action: 'chooseApps', memberId: 'maya' })
  assert.deepEqual(routineRequest({ action: 'authorize', memberId: 'maya' }), { action: 'authorize', memberId: 'maya' })
  assert.equal(routineRequest({ action: 'unlock', memberId: 'maya' }), null)
  assert.equal(routineRequest({ action: 'setup', memberId: '../leo' }), null)
})
test('routine school websites: preserve parent policy and reject malformed host lists', () => {
  const school = { ...state, allowedWebsitesOnly: true, allowedWebDomains: ['clever.com', 'student.freckle.com'] }
  assert.deepEqual(routineDecision(school, now)?.allowedWebDomains, school.allowedWebDomains)
  assert.equal(routineDecision(school, now)?.allowedWebsitesOnly, true)
  assert.equal(routineDecision({ ...school, allowedWebDomains: ['https://clever.com'] }, now), null)
  assert.equal(routineDecision({ ...school, allowedWebDomains: [] }, now), null)
  assert.equal(routineDecision({ ...school, allowedWebsitesOnly: 'true' }, now), null)
})

test('routine app modes: accept only selected or all and preserve the server policy', () => {
  assert.equal(routineDecision(state, now)?.appMode, 'selected')
  assert.equal(routineDecision({ ...state, appMode: 'all' }, now)?.appMode, 'all')
  assert.equal(routineDecision({ ...state, appMode: 'unknown' }, now), null)
})

test('routine calendar carries per-day policy without carrying yesterday’s chore approval forward', () => {
  const days = [null, null, null, null, null, null, { start: '09:00', cutoff: '21:00' }]
  const full = { ...state, date: '2026-10-22', timezone: 'America/New_York', start: '07:30', cutoff: '20:00', daySchedules: days, requiredChoreIds: null }
  assert.deepEqual(routineDecision(full, now)?.calendar, { timezone: 'America/New_York', start: '07:30', cutoff: '20:00', days, scheduleOnly: false })
  assert.equal(routineDecision(full, now)?.date, '2026-10-22')
  assert.equal(routineDecision({ ...full, requiredChoreIds: [] }, now)?.calendar?.scheduleOnly, true)
  assert.equal(routineDecision({ ...full, requiredChoreIds: ['read'] }, now)?.calendar?.scheduleOnly, false)
  assert.equal(routineDecision({ ...full, requiredChoreIds: [], requiredOneTimeChoreNames: ['Clean your room'] }, now)?.calendar?.scheduleOnly, false, 'a name rule still needs a fresh chore decision on future days')
  assert.equal(routineDecision({ ...full, requiredChoreIds: [], requiredOneTimeChoreNames: [] }, now)?.calendar?.scheduleOnly, true)
  assert.equal(routineDecision({ ...full, requiredOneTimeChoreNames: 'invalid' }, now), null)
  for (const bad of [{ timezone: 'not-a-timezone' }, { start: '21:00' }, { daySchedules: [] }, { daySchedules: [...days.slice(0, 6), { start: '22:00', cutoff: '20:00' }] }, { date: '2026-02-31' }, { requiredChoreIds: 'none' }]) assert.equal(routineDecision({ ...full, ...bad }, now), null)
})
