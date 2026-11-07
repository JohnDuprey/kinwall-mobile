import { test } from 'node:test'
import assert from 'node:assert/strict'
import { nativePushTransport, registerNativeToken, acceptsNativeToken } from '../src/nativePushTransport.ts'

test('Android push requires a Firebase-configured build; Apple keeps its entitlement gate', () => {
  assert.equal(nativePushTransport('android', false, false), null)
  assert.equal(nativePushTransport('android', true, false), 'fcm')
  assert.equal(nativePushTransport('ios', true, false), null)
  assert.equal(nativePushTransport('ios', false, true), 'apns')
  assert.equal(nativePushTransport('web', true, true), null)
  assert.equal(acceptsNativeToken('fcm', { type: 'android', data: 'fake:fcm-token' }), true)
  assert.equal(acceptsNativeToken('apns', { type: 'android', data: 'fake:fcm-token' }), false)
  assert.equal(acceptsNativeToken('fcm', { type: 'android', data: {} }), false)
})

test('FCM registration never enrolls with the Apple gateway or includes preferences/member overrides', async () => {
  const calls: unknown[] = []
  const result = { push: false, subscription: { id: 'android-phone' } }
  const deps = {
    android: async (body: unknown) => { calls.push(body); return result },
    apple: async () => { throw Error('must not use App Attest/APNs') },
  }
  assert.equal(await registerNativeToken('fcm', 'fake:fcm-token', false, deps), result)
  assert.deepEqual(calls, [{ token: 'fake:fcm-token', deviceName: 'Kinwall Android' }])
})

test('Apple registration stays on the gateway path with the existing device name', async () => {
  let body: unknown
  const result = { push: true, subscription: { id: 'ipad' } }
  await registerNativeToken('apns', 'aaaa', true, {
    android: async () => { throw Error('must not use FCM') },
    apple: async b => { body = b; return result },
  })
  assert.deepEqual(body, { token: 'aaaa', deviceName: 'Kinwall iPad' })
})
