import { test } from 'node:test'
import assert from 'node:assert/strict'
import { reminderConnection } from '../src/reminderConnection.ts'

const baseURL = 'http://localhost:8180/'
const tokens = { baseURL, accessToken: 'sam', refreshToken: 'refresh', clientId: 'phone', expiresAt: 0, scope: 'kinwall:admin' }
const paired = { baseURL, key: 'maya' }, widgets = { baseURL, key: 'shared' }
const deps = () => ({ loadTokens: async () => tokens, freshTokens: async () => ({ ...tokens, accessToken: 'fresh-sam' }), paired: async () => paired, widgets: async () => widgets })

test('medicine fallback uses the signed-in person instead of the shared widgets identity', async () => {
  assert.deepEqual(await reminderConnection(baseURL, deps()), { baseURL, key: 'fresh-sam' })
})
test('paired devices use their own credential, with legacy widgets as a fallback', async () => {
  const d = { ...deps(), loadTokens: async () => null }
  assert.deepEqual(await reminderConnection(baseURL, d), paired)
  assert.deepEqual(await reminderConnection(baseURL, { ...d, paired: async () => null }), widgets)
})
test('revoked OAuth cannot fall back to an old device identity', async () => {
  assert.equal(await reminderConnection(baseURL, { ...deps(), freshTokens: async () => null }), null)
})
test('signed-out or other-server credentials never schedule reminders', async () => {
  assert.equal(await reminderConnection(null, deps()), null)
  assert.equal(await reminderConnection('https://other.invalid/', deps()), null)
})
