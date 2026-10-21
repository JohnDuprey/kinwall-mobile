import { test } from 'node:test'
import assert from 'node:assert/strict'
import { personalWatchConnection } from '../src/watchConnection.ts'
import { createDeviceKey, revokeOwnKey, watchKeyFits } from '../src/api.ts'
const api = { createDeviceKey, revokeOwnKey, watchKeyFits }

const source = { baseURL: 'https://kinwall.invalid', key: 'phone' }
const saved = { baseURL: source.baseURL, key: 'old-watch' }

test('a legacy shared Watch key is replaced directly from the phone, then revoked', async () => {
  const calls: { key: string; path: string; method: string; body?: unknown }[] = []
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    const key = String((init.headers as Record<string, string>).Authorization).replace('Bearer ', '')
    const path = new URL(url).pathname
    const method = init.method ?? 'GET'
    calls.push({ key, path, method, ...(init.body ? { body: JSON.parse(String(init.body)) } : {}) })
    if (path === '/api/me') return new Response(JSON.stringify({ householdId: 'demo', owner: key === 'phone' ? 'm1' : 'shared', scope: key === 'phone' ? 'admin' : 'display' }))
    return new Response(JSON.stringify(method === 'POST' ? { id: 'new', key: 'personal-watch' } : { ok: true }))
  }) as typeof fetch
  assert.deepEqual(await personalWatchConnection(source, saved, () => true, api), { baseURL: source.baseURL, key: 'personal-watch' })
  assert.deepEqual(calls.filter(c => c.method === 'POST'), [{ key: 'phone', path: '/api/device-keys', method: 'POST', body: { name: 'Apple Watch', purpose: 'watch' } }])
  assert.deepEqual(calls.filter(c => c.method === 'DELETE'), [{ key: 'old-watch', path: '/api/device-keys/self', method: 'DELETE' }])
})

test('a sign-out during key creation revokes the unused key and never sends it', async () => {
  const revoked: string[] = []
  globalThis.fetch = (async (_url: string, init: RequestInit) => {
    if (init.method === 'DELETE') revoked.push(String((init.headers as Record<string, string>).Authorization))
    return new Response(JSON.stringify(init.method === 'POST' ? { id: 'new', key: 'unused-watch' } : { ok: true }))
  }) as typeof fetch
  assert.equal(await personalWatchConnection(source, null, () => false, api), null)
  assert.deepEqual(revoked, ['Bearer unused-watch'])
})


test('a sign-out while retiring the old key also revokes its replacement', async () => {
  let current = true
  const revoked: string[] = []
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    const key = String((init.headers as Record<string, string>).Authorization).replace('Bearer ', '')
    if (new URL(url).pathname === '/api/me') return new Response(JSON.stringify({ householdId: 'demo', owner: key === 'phone' ? 'm1' : 'shared' }))
    if (init.method === 'DELETE') { revoked.push(key); if (key === 'old-watch') current = false }
    return new Response(JSON.stringify(init.method === 'POST' ? { id: 'new', key: 'unused-watch' } : { ok: true }))
  }) as typeof fetch
  assert.equal(await personalWatchConnection(source, saved, () => current, api), null)
  assert.deepEqual(revoked, ['old-watch', 'unused-watch'])
})
