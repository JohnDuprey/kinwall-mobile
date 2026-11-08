import { test } from 'node:test'
import assert from 'node:assert/strict'
import { NativePushSession, pushRegistrationActive } from '../src/nativePushSession.ts'

test('native push: expired gateway credentials restore local reminders; direct push does not expire', () => {
  const r = { baseURL: 'https://family.example', id: 'phone', push: true }
  assert.equal(pushRegistrationActive({ ...r, expiresAt: 200 }, r.baseURL, 100), true)
  assert.equal(pushRegistrationActive({ ...r, expiresAt: 200 }, r.baseURL, 201), false)
  assert.equal(pushRegistrationActive(r, r.baseURL, 201), true)
});

test('native push: signing out during registration removes the late token before another family signs in', async () => {
  const events: string[] = []
  let finish!: (r: { push: boolean; subscription: { id: string } }) => void
  const session = new NativePushSession({
    register: async c => { events.push(`put:${c.baseURL}`); return new Promise(r => { finish = r }) },
    remove: async (c, id) => { events.push(`delete:${c.baseURL}:${id}`) },
    changed: r => { events.push(`save:${r?.id ?? 'off'}`) },
  })
  session.setDevice({ baseURL: 'https://old.example', key: 'old' })
  const saving = session.register('aa')
  await new Promise(r => setImmediate(r))
  const clearing = session.clear()
  finish({ push: true, subscription: { id: 'late' } })
  await Promise.all([saving, clearing])
  assert.deepEqual(events, ['put:https://old.example', 'delete:https://old.example:late', 'save:off'])
})

test('native push: registration failure keeps a working registration; permission revocation clears it', async () => {
  let fail = false
  const removed: string[] = []
  const session = new NativePushSession({ register: async () => { if (fail) throw new Error('offline'); return { push: true, subscription: { id: 'phone' } } },
    remove: async (_, id) => { removed.push(id) }, changed: () => {} })
  session.setDevice({ baseURL: 'https://family.example', key: 'one' })
  await session.register('aa'); assert.equal(session.registration?.push, true)
  fail = true
  await assert.rejects(session.register('bb'))
  assert.equal(session.registration?.id, 'phone')
  await session.clear()
  assert.equal(session.registration, null)
  assert.deepEqual(removed, ['phone'])
})

test('Android reconnect and token rotation retain the device subscription without sending preference defaults', async () => {
  const calls: unknown[] = [], removed: string[] = []
  const session = new NativePushSession({
    register: async (c, token) => { calls.push({ c, token }); return { push: true, subscription: { id: 'android-phone' } } },
    remove: async (_, id) => { removed.push(id) }, changed: () => {},
  })
  session.setDevice({ baseURL: 'https://family.example', key: 'oauth-one' })
  await session.register('fake:fcm-one')
  session.setDevice({ baseURL: 'https://family.example', key: 'oauth-refreshed' })
  await session.register('fake:fcm-rotated')
  assert.equal(session.registration?.id, 'android-phone')
  assert.deepEqual(calls, [
    { c: { baseURL: 'https://family.example', key: 'oauth-one' }, token: 'fake:fcm-one' },
    { c: { baseURL: 'https://family.example', key: 'oauth-refreshed' }, token: 'fake:fcm-rotated' },
  ])
  await session.clear()
  assert.deepEqual(removed, ['android-phone'])
  assert.equal(session.registration, null)
})

// The app re-registers on every resume and page load; on 2026-11-08 one phone sent 35 identical
// registrations in two minutes. An unchanged one inside REREGISTER_MS is skipped.
test('native push: an unchanged registration is not sent again until it is due', async () => {
  let now = 0
  const sent: string[] = []
  const session = new NativePushSession({
    register: async (c, token) => { sent.push(`${c.key}:${token}`); return { push: true, subscription: { id: 'phone' }, gatewayExpiresAt: now + 7 * 86400_000 } },
    remove: async () => {}, changed: () => {}, now: () => now,
  })
  session.setDevice({ baseURL: 'https://family.example', key: 'one' })
  await session.register('aa')
  await session.register('aa'); await session.register('aa')
  assert.deepEqual(sent, ['one:aa'])
  await session.register('bb') // rotated token
  session.setDevice({ baseURL: 'https://family.example', key: 'two' })
  await session.register('bb') // refreshed key
  now += 12 * 3600_000
  await session.register('bb') // due again
  assert.deepEqual(sent, ['one:aa', 'one:bb', 'two:bb', 'two:bb'])
  now += 6.5 * 86400_000 // gateway credential expires within a day
  await session.register('bb')
  assert.equal(sent.length, 5)
  await session.clear()
  session.setDevice({ baseURL: 'https://family.example', key: 'two' })
  await session.register('bb') // turned off and on again
  assert.equal(sent.length, 6)
})
