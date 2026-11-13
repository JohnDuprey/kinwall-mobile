// node --test test/ (npm test). The saved server address moves to "after first unlock" (src/server.ts)
// so the reminders' background refresh can read it while the phone is locked. iOS keeps an existing
// Keychain item's accessibility when only its value is updated, so the move deletes and saves again.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { resave } from '../src/keychainResave.ts'

function keychain(value: string | null, failSave = false) {
  const k = { value, accessible: 'whenUnlocked' as string | null, calls: [] as string[] }
  return {
    k,
    store: {
      get: async () => { k.calls.push('get'); return k.value },
      remove: async () => { k.calls.push('remove'); k.value = null; k.accessible = null },
      save: async (v: string) => { k.calls.push('save'); if (failSave) throw new Error('Keychain busy'); k.value = v; k.accessible = 'afterFirstUnlock' },
      restore: async (v: string) => { k.calls.push('restore'); k.value = v; k.accessible = 'whenUnlocked' },
    },
  }
}

test('resave: the saved value is deleted and saved again with the new accessibility', async () => {
  const { k, store } = keychain('https://ourfamily.kinwall.family/')
  assert.equal(await resave(store), true)
  assert.deepEqual(k.calls, ['get', 'remove', 'save'])
  assert.equal(k.value, 'https://ourfamily.kinwall.family/')
  assert.equal(k.accessible, 'afterFirstUnlock')
})

test('resave: nothing saved means nothing to move', async () => {
  const { k, store } = keychain(null)
  assert.equal(await resave(store), true)
  assert.deepEqual(k.calls, ['get'])
})

test('resave: a failed save puts the address back as it was', async () => {
  const { k, store } = keychain('http://kinwall.local:8080/', true)
  await assert.rejects(resave(store), /Keychain busy/)
  assert.equal(k.value, 'http://kinwall.local:8080/')
  assert.equal(k.accessible, 'whenUnlocked')
})

test('resave: a failed read (the phone locked) changes nothing', async () => {
  const { k, store } = keychain('https://ourfamily.kinwall.family/')
  store.get = async () => { throw new Error('User interaction is not allowed') }
  await assert.rejects(resave(store))
  assert.equal(k.value, 'https://ourfamily.kinwall.family/')
  assert.deepEqual(k.calls, [])
})
