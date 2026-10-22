import { test } from 'node:test'
import assert from 'node:assert/strict'
import { NativePushSession } from '../src/nativePushSession.ts'

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
