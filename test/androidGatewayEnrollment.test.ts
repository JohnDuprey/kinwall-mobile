import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { AndroidGatewayEnrollmentClient, type AndroidGatewayState } from '../src/androidGatewayEnrollment.ts'
import { registerAndroidPush } from '../src/androidPushRegistration.ts'
import { GatewayHTTPError } from '../src/gatewayEnrollment.ts'

const hash = (s: string) => createHash('sha256').update(s).digest('hex')
const hash64 = (s: string) => createHash('sha256').update(s).digest('base64url')
const input = { server: 'https://family.example', token: 'Fake:FCM_Case-Sensitive', kind: 'android-alert' as const }
const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
const credential = `android-v1.${id}.${'b'.repeat(64)}`
function fixture() {
  let state: AndroidGatewayState | null = null, now = 1000000, offline = false, supported = true
  const calls: { path: string; body?: any; method?: string; credential?: string }[] = [], proofs: string[] = []
  const deps = {
    supported: () => supported,
    publicKey: async () => ({ publicKey: 'fake-spki', keyId: hash('fake-key') }),
    hash: async (text: string, encoding: 'hex' | 'base64url') => encoding === 'hex' ? hash(text) : hash64(text),
    proof: async (data: string) => { proofs.push(data); return { integrityToken: 'fake-google-proof', signature: 'fake-key-signature' } },
    load: async () => structuredClone(state), save: async (s: AndroidGatewayState) => { state = structuredClone(s) }, now: () => now,
    request: async (path: string, body?: any, method?: 'POST'|'DELETE', bearer?: string): Promise<unknown> => {
      calls.push({ path, body, method, credential: bearer })
      if (offline) throw new Error('offline')
      if (path.endsWith('/challenge')) {
        const clientData = JSON.stringify({ protocol: 'kinwall-android-push-v1', challenge: 'c'.repeat(64), keyId: hash('fake-key'), tokenHash: hash(body.registration.token), server: body.registration.server, kind: 'android-alert' })
        return { id: 'fake-challenge', clientData, requestHash: hash64(clientData), expiresAt: now + 300000 }
      }
      if (path.endsWith('/register')) return { id, credential, expiresAt: now + 30 * 86400000 }
      return { revoked: true }
    },
  }
  return { client: new AndroidGatewayEnrollmentClient(deps), deps, calls, proofs, state: () => state, advance: (ms: number) => { now += ms }, offline: (on: boolean) => { offline = on }, supported: (on: boolean) => { supported = on } }
}
test('Android gateway binds raw case-sensitive FCM, key, canonical origin, kind and exact request hash', async () => {
  const f = fixture()
  assert.equal((await f.client.get({ ...input, server: input.server + '/path' })).credential, credential)
  assert.deepEqual(f.calls[0]!.body.registration, input)
  const data = JSON.parse(f.proofs[0]!)
  assert.equal(data.tokenHash, hash(input.token)); assert.equal(data.server, input.server)
  assert.equal(f.calls[1]!.body.integrityToken, 'fake-google-proof')
  assert.equal(f.calls[1]!.body.signature, 'fake-key-signature')
  await f.client.get(input); assert.equal(f.calls.length, 2)
  f.advance(30 * 86400000 - 240000)
  await f.client.get(input); assert.equal(f.proofs.length, 2, 'renewal always gets fresh Integrity proof')
  assert.equal(f.state()!.pending.length, 0, 'same row renewal must not revoke new bearer')
})
test('Android gateway rejects changed fields, reordered JSON, wrong hash and expired challenges before proof', async () => {
  for (const field of ['server', 'tokenHash', 'keyId', 'kind', 'protocol', 'extra', 'order', 'hash', 'expiry']) {
    const f = fixture(), request = f.deps.request
    f.deps.request = async (...args) => {
      const result = await request(...args) as any
      if (!args[0].endsWith('/challenge')) return result
      const data = JSON.parse(result.clientData)
      if (field === 'hash') result.requestHash = 'x'.repeat(43)
      else if (field === 'expiry') result.expiresAt = 1
      else {
        if (field === 'order') result.clientData = JSON.stringify({ kind: data.kind, ...data })
        else { data[field] = 'changed'; result.clientData = JSON.stringify(data) }
        result.requestHash = hash64(result.clientData)
      }
      return result
    }
    await assert.rejects(f.client.get(input), /challenge/i, field)
    assert.equal(f.proofs.length, 0, field)
  }
})
test('Android gateway fails closed for missing configuration, invalid origins, tokens and Apple credentials', async () => {
  const f = fixture(); f.supported(false)
  await assert.rejects(f.client.get(input), /unavailable/); assert.equal(f.calls.length, 0)
  for (const server of ['file:///tmp/a', 'https://user:pass@family.example']) await assert.rejects(f.client.get({ ...input, server }))
  for (const token of ['', ' bad token ', 'a\nb']) await assert.rejects(f.client.get({ ...input, token }))
  const g = fixture(), request = g.deps.request
  g.deps.request = async (...args) => args[0].endsWith('/register') ? { id, credential: `${id}.${'b'.repeat(64)}`, expiresAt: 2000000 } : request(...args)
  await assert.rejects(g.client.get(input), /registration/i)
})
test('Android offline signout is durably queued, isolated by origin and retried after restart', async () => {
  const f = fixture(); await f.client.get(input)
  f.offline(true); await f.client.revokeServer('https://other.example')
  assert.equal(f.state()!.registrations.length, 1)
  await f.client.revokeServer(input.server)
  assert.equal(f.state()!.registrations.length, 0); assert.equal(f.state()!.pending.length, 1)
  f.offline(false); await new AndroidGatewayEnrollmentClient(f.deps).flushRevocations()
  assert.equal(f.state()!.pending.length, 0)
  assert.equal(f.calls.at(-1)!.path, '/v1/android/registration')
  assert.equal(f.calls.at(-1)!.credential, credential)
})
test('Android rotation queues previous capability without revoking renewed row and treats 401 as complete', async () => {
  const f = fixture(); await f.client.get(input)
  const request = f.deps.request, nextId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
  f.deps.request = async (...args) => {
    if (args[2] === 'DELETE') throw new GatewayHTTPError(401)
    if (args[0].endsWith('/register')) return { id: nextId, credential: `android-v1.${nextId}.${'d'.repeat(64)}`, expiresAt: 2000000 }
    return request(...args)
  }
  await f.client.get({ ...input, token: input.token.toLowerCase() })
  assert.equal(f.state()!.registrations.length, 1)
  assert.equal(f.state()!.registrations[0]!.token, input.token.toLowerCase())
  assert.equal(f.state()!.pending.length, 0)
})
test('Android signout queued during enrollment retires its late credential', async () => {
  const f = fixture(), request = f.deps.request
  let finish!: () => void
  f.deps.request = async (...args) => { if (args[0].endsWith('/register')) await new Promise<void>(resolve => { finish = resolve }); return request(...args) }
  const enrolling = f.client.get(input)
  await new Promise(r => setImmediate(r))
  const clearing = f.client.revokeServer(input.server)
  finish(); await Promise.all([enrolling, clearing])
  assert.equal(f.state()!.registrations.length, 0)
  assert.equal(f.calls.at(-1)!.method, 'DELETE')
})

test('Android direct readiness after token rotation retires the previous capability by origin', async () => {
  const f = fixture(); await f.client.get(input)
  const request = f.deps.request
  f.deps.request = async (...args) => {
    if (args[0].endsWith('/register') && args[1].registration.server === 'https://other.example') {
      const otherId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
      return { id: otherId, credential: `android-v1.${otherId}.${'f'.repeat(64)}`, expiresAt: 2000000 }
    }
    return request(...args)
  }
  await f.client.get({ ...input, server: 'https://other.example' })
  const bodies: unknown[] = []
  const result = await registerAndroidPush({ baseURL: input.server + '/path', key: 'fake-key' }, { token: 'Fake:ROTATED', deviceName: 'Kinwall Android' }, {
    client: f.client, current: () => true,
    register: async body => { bodies.push(body); return { push: true, delivery: 'direct' } },
  })
  assert.equal(result.push, true)
  assert.deepEqual(f.state()!.registrations.map(r => r.server), ['https://other.example'], 'previous-token capability must no longer be reusable')
  const deletes = f.calls.filter(c => c.method === 'DELETE')
  assert.equal(deletes.length, 1); assert.equal(deletes[0]!.credential, credential)
  assert.deepEqual(bodies, [{ token: 'Fake:ROTATED', deviceName: 'Kinwall Android' }], 'direct readiness needs one server handoff and no gateway send')
  assert.equal(f.proofs.length, 2, 'direct readiness must not enroll the rotated token')
})

test('Android direct rotation persists offline cleanup and retries it after restart without a duplicate handoff', async () => {
  const f = fixture(); await f.client.get(input); f.offline(true)
  let handoffs = 0
  const deps = { client: f.client, current: () => true, register: async () => { handoffs++; return { push: true, delivery: 'direct' as const } } }
  assert.equal((await registerAndroidPush({ baseURL: input.server, key: 'fake-key' }, { token: 'Fake:ROTATED', deviceName: 'Kinwall Android' }, deps)).push, true)
  assert.equal(f.state()!.registrations.length, 0)
  assert.equal(f.state()!.pending.length, 1)
  f.offline(false)
  await new AndroidGatewayEnrollmentClient(f.deps).flushRevocations()
  await new AndroidGatewayEnrollmentClient(f.deps).flushRevocations()
  assert.equal(f.state()!.pending.length, 0)
  assert.equal(f.calls.filter(c => c.method === 'DELETE').length, 2, 'one failed delete and one successful retry')
  assert.equal(handoffs, 1)
})

test('Android unavailable direct response and failed renewal retain the existing capability and local readiness', async () => {
  for (const delivery of ['direct', 'gateway'] as const) {
    const f = fixture(); await f.client.get(input)
    const result = await registerAndroidPush({ baseURL: input.server, key: 'fake-key' }, { token: input.token, deviceName: 'Kinwall Android' }, {
      client: { get: async () => { throw new Error('offline') }, revoke: i => f.client.revoke(i), revokeServer: s => f.client.revokeServer(s) },
      current: () => true,
      register: async () => ({ push: delivery === 'gateway', delivery, gatewayAvailable: true, gatewayExpiresAt: Date.now() + 60000 }),
    })
    assert.equal(result.push, delivery === 'gateway')
    assert.equal(f.state()!.registrations.length, 1)
    assert.equal(f.calls.filter(c => c.method === 'DELETE').length, 0)
  }
})

test('Android direct handoff after enrollment removes the issued capability without a third registration', async () => {
  const f = fixture(); let handoffs = 0
  const result = await registerAndroidPush({ baseURL: input.server, key: 'fake-key' }, { token: input.token, deviceName: 'Kinwall Android' }, {
    client: f.client, current: () => true,
    register: async body => {
      handoffs++
      if (!body.gateway) return { push: false, delivery: 'unavailable', gatewayAvailable: true }
      assert.equal(body.gateway.credential, credential)
      return { push: true, delivery: 'direct', gatewayAvailable: true }
    },
  })
  assert.equal(result.push, true); assert.equal(handoffs, 2)
  assert.equal(f.state()!.registrations.length, 0)
  assert.equal(f.calls.filter(c => c.method === 'DELETE').length, 1)
})
test('Android gateway: a credential enrolled for the canonical address is revoked when leaving the address the app connects through', async () => {
  const f = fixture()
  await f.client.get({ ...input, app: 'http://192.168.1.20:8080/' })
  assert.deepEqual(f.calls[0]!.body.registration, input, 'the gateway sees only the canonical registration')
  await f.client.revokeServer('http://192.168.1.20:8080')
  assert.equal(f.state()!.registrations.length, 0)
  assert.ok(f.calls.some(c => c.method === 'DELETE' && c.credential === credential))
})
