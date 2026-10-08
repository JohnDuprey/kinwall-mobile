// node --test test/ (npm test). The app's refresh of its OAuth sign-in (src/tokenRefresh.ts), which
// the share sheet and Siri also refresh in their own process.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { refreshed, type Store } from '../src/tokenRefresh.ts'

const base = 'https://kinwall.family/'
const tokens = (refresh: string, inMinutes: number) =>
  ({ baseURL: base, clientId: 'c', accessToken: `a-${refresh}`, refreshToken: refresh, expiresAt: Date.now() + inMinutes * 60_000, scope: 'kinwall:admin' })
const gone = Object.assign(new Error('used'), { code: 'invalid_grant' })

/** A Keychain holding `saved` (another process may change it), and a server answering `answer`. */
function store(saved: ReturnType<typeof tokens> | null, answer: (t: ReturnType<typeof tokens>) => ReturnType<typeof tokens>, onRefresh = () => {}) {
  const s = { saved, saves: 0, sent: [] as string[] }
  const deps: Store = {
    load: async () => s.saved,
    refresh: async (t) => { s.sent.push(t.refreshToken); onRefresh(); return answer(t) },
    save: async (t) => { s.saves++; s.saved = t },
  }
  return { s, deps }
}

test('refreshed: starts from the saved tokens, which another process may have refreshed already', async () => {
  const { s, deps } = store(tokens('r2', 60), () => assert.fail('refreshed again'))
  assert.equal((await refreshed(tokens('r1', 2), false, deps))?.refreshToken, 'r2')
  assert.deepEqual(s.sent, [])
})

test('refreshed: a due refresh is saved before use', async () => {
  const { s, deps } = store(tokens('r1', 2), () => tokens('r2', 60))
  assert.equal((await refreshed(tokens('r1', 2), false, deps))?.refreshToken, 'r2')
  assert.equal(s.saved?.refreshToken, 'r2')
})

test('refreshed: turned down after the share sheet rotated them meanwhile, it uses theirs', async () => {
  // The share extension saves r2 while this refresh with r1 is on its way, and the server says no.
  const { deps, s } = store(tokens('r1', 2), () => { throw gone }, () => { s.saved = tokens('r2', 60) })
  assert.equal((await refreshed(tokens('r1', 2), false, deps))?.refreshToken, 'r2')
})

test('refreshed: turned down with nothing newer saved means sign in again', async () => {
  const { deps } = store(tokens('r1', 2), () => { throw gone })
  assert.equal(await refreshed(tokens('r1', 2), false, deps), null)
})

test('refreshed: offline keeps the old tokens to try again later', async () => {
  const { deps } = store(tokens('r1', 2), () => { throw new TypeError('Network request failed') })
  assert.equal((await refreshed(tokens('r1', 2), false, deps))?.refreshToken, 'r1')
})

test('refreshed: a failed save is tried once more and the new pair still used', async () => {
  let tries = 0
  const deps: Store = { load: async () => null, refresh: async () => tokens('r2', 60), save: async () => { tries++; throw new Error('Keychain status -25308') } }
  assert.equal((await refreshed(tokens('r1', 2), false, deps))?.refreshToken, 'r2')
  assert.equal(tries, 2)
})

test('refreshed: forced, the saved ones do when they are newer than the rejected key', async () => {
  const { s, deps } = store(tokens('r2', 60), () => tokens('r3', 60))
  assert.equal((await refreshed(tokens('r1', 60), true, deps))?.refreshToken, 'r2')
  assert.equal((await refreshed(tokens('r2', 60), true, deps))?.refreshToken, 'r3')
  assert.deepEqual(s.sent, ['r2'])
})
