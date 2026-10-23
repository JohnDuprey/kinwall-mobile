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
