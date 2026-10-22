import { test } from 'node:test'
import assert from 'node:assert/strict'
import { registerPush } from '../src/pushGatewayRegistration.ts'

const c = { baseURL: 'https://family.example', key: 'device-key' }
const token = 'ab'.repeat(32)
test('push registration: hosted takes the direct path without contacting the gateway', async () => {
  let enrolled = false
  const result = await registerPush(c, { token }, 'alert', {
    register: async () => ({ push: true, delivery: 'direct', subscription: { id: 'phone' } }),
    enroll: async () => { enrolled = true; throw new Error('must not enroll hosted') },
    revoke: async () => {},
  })
  assert.equal(result.push, true); assert.equal(enrolled, false)
});
test('push registration: self-hosted enrolls only after the server reports unavailable', async () => {
  const bodies: any[] = []
  const result = await registerPush(c, { token }, 'alert', {
    register: async body => { bodies.push(body); return { push: !!body.gateway, delivery: body.gateway ? 'gateway' : 'unavailable', subscription: { id: 'phone' } } },
    enroll: async () => ({ credential: 'scoped-device-credential', expiresAt: Date.now() + 3600000 }),
    revoke: async () => {},
  })
  assert.equal(result.push, true)
  assert.deepEqual(bodies, [{ token }, { token, gateway: { credential: 'scoped-device-credential' } }])
});
test('push registration: failed enrollment preserves the local-reminder fallback', async () => {
  const result = await registerPush(c, { token }, 'alert', {
    register: async () => ({ push: false, delivery: 'unavailable', subscription: { id: 'phone' } }),
    enroll: async () => { throw new Error('attestation unavailable') },
    revoke: async () => {},
  })
  assert.equal(result.push, false)
});

test('push registration: older working servers skip gateway enrollment', async () => {
  const result = await registerPush(c, { token }, 'alert', {
    register: async () => ({ push: true }),
    enroll: async () => { throw new Error('must not enroll'); }, revoke: async () => { assert.fail('must not revoke') },
  })
  assert.equal(result.push, true)
})
test('push registration: cancellation and failed handoff revoke newly issued credentials', async () => {
  for (const cancelled of [true, false]) {
    let revoked = 0, calls = 0
    const result = await registerPush(c, { token }, 'alert', {
      register: async () => { if (++calls > 1) throw new Error('handoff timed out'); return { push: false, delivery: 'unavailable' } },
      enroll: async () => ({ credential: 'scoped', expiresAt: Date.now() + 3600000 }),
      revoke: async () => { revoked++ }, current: () => !cancelled,
    })
    assert.equal(revoked, 1); assert.equal(result.push, false)
    assert.equal(calls, cancelled ? 1 : 2)
  }
})
test('push registration: failed renewal preserves a working credential until its expiry', async () => {
  let revoked = 0
  const result = await registerPush(c, { token }, 'alert', {
    register: async () => ({ push: true, delivery: 'gateway', gatewayExpiresAt: Date.now() + 60000 }),
    enroll: async () => { throw new Error('offline') }, revoke: async () => { revoked++ },
  })
  assert.equal(result.push, true); assert.equal(revoked, 0)
})
test('push registration: an older unavailable server keeps local reminders without issuing an unusable credential', async () => {
  const result = await registerPush(c, { token }, 'alert', {
    register: async () => ({ push: false }),
    enroll: async () => { assert.fail('older servers cannot accept a gateway capability') }, revoke: async () => {},
  })
  assert.equal(result.push, false)
})
