import { test } from 'node:test'
import assert from 'node:assert/strict'
import { runRoutineNotification } from '../src/routineNotification.ts'

const wake = (server = 'https://our-family.kinwall.family') => ({ notification: null, aps: { 'content-available': 1 }, data: { kinwall: { type: 'routine-sync', server } } })
test('a routine background notification supplies only an origin hint to authenticated refresh', async () => {
  const origins: string[] = []
  assert.equal(await runRoutineNotification(wake(), async origin => { origins.push(origin); return {} }), 0)
  assert.deepEqual(origins, ['https://our-family.kinwall.family'])
  assert.equal(await runRoutineNotification(wake(), async () => null), 1)
})
test('alerts, action responses, malformed or oversized origins never start routine refresh', async () => {
  for (const payload of [null, {}, { data: { kinwall: { type: 'unlock', server: 'https://our-family.kinwall.family' } } }, { ...wake(), actionIdentifier: 'open' }, { ...wake(), notification: { title: 'Hello' } }, { ...wake(), aps: {} }, ...['javascript:alert(1)', 'https://other.invalid/path', 'https://name:pass@other.invalid', '//other.invalid', 'x'.repeat(3000)].map(wake)]) {
    assert.equal(await runRoutineNotification(payload, async () => { assert.fail('unexpected routine wake') }), 1)
  }
})
test('refresh failure is reported to iOS without throwing or treating the payload as an unlock', async () => {
  assert.equal(await runRoutineNotification(wake(), async () => { throw new Error('offline') }), 2)
  let value: unknown
  await runRoutineNotification({ ...wake(), locked: false, validUntil: '2099-01-01', memberId: 'leo' }, async origin => { value = origin; return {} })
  assert.equal(value, 'https://our-family.kinwall.family')
})
