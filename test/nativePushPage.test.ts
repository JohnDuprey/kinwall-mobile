import { test } from 'node:test'
import assert from 'node:assert/strict'
import vm from 'node:vm'
import { nativePushPageScript } from '../src/nativePushPage.ts'

const server = 'https://family.example/'
function page(registration: unknown, origin = 'https://family.example', enabled = true) {
  const storage = new Map([['kinwall.pushSubId', 'stale']])
  const native: Record<string, unknown> = {}
  const context = { location: { origin }, window: { kinwallNative: native, dispatchEvent() {} },
    localStorage: { setItem: (k: string, v: string) => storage.set(k, v), removeItem: (k: string) => storage.delete(k) }, Event: class {} }
  vm.runInNewContext(nativePushPageScript(server, registration as never, enabled, 100), context)
  return { storage, native }
}
test('subscription metadata survives a page reload without exposing tokens or resetting newChores', () => {
  const reg = { baseURL: server, id: 'phone', push: true, token: 'secret', prefs: { newChores: true } }
  const p = page(reg)
  assert.equal(p.storage.get('kinwall.pushSubId'), 'phone')
  assert.equal(p.native.pushReady, true)
  assert.doesNotMatch(nativePushPageScript(server, reg, true), /secret|newChores/)
})
test('expired, other-family and demo registrations never advertise ready', () => {
  assert.equal(page({ baseURL: server, id: 'phone', push: true, expiresAt: 99 }).native.pushReady, false)
  for (const reg of [null, { baseURL: 'https://old.example/', id: 'old', push: true }]) {
    const p = page(reg)
    assert.equal(p.native.pushReady, false)
    assert.equal(p.storage.has('kinwall.pushSubId'), false)
  }
  const demo = page({ baseURL: server, id: 'phone', push: true }, undefined, false)
  assert.equal(demo.storage.has('kinwall.pushSubId'), false)
  assert.equal(demo.native.pushReady, false)
  assert.equal(page(null, 'https://untrusted.example').storage.get('kinwall.pushSubId'), 'stale')
})
