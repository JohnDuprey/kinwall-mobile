import { test } from 'node:test'
import assert from 'node:assert/strict'
import { GatewayEnrollmentClient, type GatewayState } from '../src/gatewayEnrollment.ts'

const input = { token: 'ab'.repeat(32), server: 'https://family.example', kind: 'alert' as const }
const credential = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.' + 'b'.repeat(64)
function fixture() {
  let state: GatewayState | null = null, now = 1000000, offline = false
  const calls: string[] = []
  const deps = {
    supported: () => true, generateKey: async () => 'test-key',
    attestKey: async (_key: string, _challenge: string) => 'attestation', assertion: async (_key: string, _data: string) => 'assertion',
    load: async () => structuredClone(state), save: async (s: GatewayState) => { state = structuredClone(s) }, now: () => now,
    request: async (path: string, body?: unknown, method?: 'POST'|'DELETE', credential?: string): Promise<unknown> => {
      calls.push(`${method ?? 'POST'} ${path}`)
      if (offline) throw new Error('offline')
      if (path.endsWith('/registration/challenge')) {
        const data = body as any, challenge = 'a'.repeat(64)
        return { id: 'challenge', challenge, clientData: JSON.stringify({ challenge, keyId: data.keyId, ...data.registration }), expiresAt: now + 300000 }
      }
      if (path.endsWith('/challenge')) return { id: 'challenge', challenge: 'a'.repeat(64), expiresAt: now + 300000 }
      if (path.endsWith('/attest')) return { verified: true }
      if (path.endsWith('/register')) {
        const token = (body as any).registration.token
        return { id: 'id', credential: token === input.token ? 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.' + 'b'.repeat(64) : 'cccccccc-cccc-cccc-cccc-cccccccccccc.' + 'd'.repeat(64), expiresAt: now + 3600000 }
      }
      return { revoked: true }
    },
  }
  const client = new GatewayEnrollmentClient(deps)
  return { client, deps, calls, getState: () => state, advance: () => { now += 3600000 }, setOffline: (value: boolean) => { offline = value } }
}

test('gateway client: attests once, caches credentials and renews expiry using an assertion', async () => {
  const { client, calls, advance } = fixture()
  assert.equal((await client.get(input)).credential, credential)
  assert.equal(calls.length, 4)
  await client.get(input)
  assert.equal(calls.length, 4)
  advance(); await client.get(input)
  assert.equal(calls.length, 6, 'renewal skips Apple attestation')
});

test('gateway client: server isolation and offline sign-out revocations survive restart', async () => {
  const { client, calls, getState, setOffline } = fixture()
  await client.get(input)
  setOffline(true)
  await client.revokeServer(input.server)
  assert.equal(getState()!.registrations.length, 0)
  assert.equal(getState()!.pending.length, 1)
  setOffline(false)
  await client.flushRevocations()
  assert.equal(getState()!.pending.length, 0)
  assert.equal(calls.at(-1), 'DELETE /v1/registration')
});

test('gateway client: token replacement retires only the old server capability', async () => {
  const { client, getState, calls } = fixture()
  await client.get(input)
  const replacement = await client.get({ ...input, token: 'cd'.repeat(32) })
  assert.notEqual(replacement.credential, credential)
  assert.equal(getState()!.registrations.length, 1)
  assert.equal(getState()!.registrations[0].token, 'cd'.repeat(32))
  assert.ok(calls.includes('DELETE /v1/registration'))
})
test('gateway client: an invalid Secure Enclave key recovers with a new attestation once', async () => {
  const { client, deps, calls } = fixture()
  let proofs = 0, keys = 0
  deps.generateKey = async () => `replacement-key-${++keys}`
  deps.assertion = async () => {
    if (++proofs === 1) throw Object.assign(new Error('invalid key'), { code: 'ERR_APP_ATTEST_INVALID_KEY' })
    return 'assertion'
  }
  await client.get(input)
  assert.equal(keys, 2)
  assert.equal(calls.filter(c => c.endsWith('/attest')).length, 2)
})
test('gateway client: changed canonical registration data is never signed', async () => {
  const { client, deps } = fixture()
  const request = deps.request
  deps.request = async (...args) => {
    const result = await request(...args) as any
    return args[0].endsWith('/registration/challenge') ? { ...result, clientData: result.clientData + 'changed' } : result
  }
  deps.assertion = async () => { assert.fail('must not sign a different registration') }
  await assert.rejects(client.get(input), /Registration challenge changed/)
})
test('gateway client: offline revocations survive a new client instance', async () => {
  const { client, deps, getState, setOffline } = fixture()
  await client.get(input)
  setOffline(true); await client.revokeServer(input.server)
  assert.equal(getState()!.pending.length, 1)
  setOffline(false)
  await new GatewayEnrollmentClient(deps).flushRevocations()
  assert.equal(getState()!.pending.length, 0)
})
