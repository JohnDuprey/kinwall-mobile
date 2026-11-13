// node --test test/ (npm test). When the app replaces the widgets' key (src/sharedKey.ts ensureWidgetKey):
// Siri said it added garlic while the widgets' key opened another household.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { widgetKeyFits } from '../src/api.ts'

const server = 'https://kinwall.family/'
/** GET /api/me answers per key: a household id, a status, or no id (an older server). */
function serve(answers: Record<string, string | number | null>) {
  globalThis.fetch = (async (_url: string, init: RequestInit) => {
    const a = answers[String((init.headers as Record<string, string>).Authorization).replace('Bearer ', '')]
    if (typeof a === 'number') return new Response(JSON.stringify({ error: 'no' }), { status: a })
    return new Response(JSON.stringify({ scope: 'admin', owner: null, ...(a ? { householdId: a } : {}) }))
  }) as typeof fetch
}

test('widgetKeyFits: same household keeps the key; another household, a revoked key or another server replaces it', async () => {
  const app = { baseURL: server, key: 'app' }
  serve({ app: 'duprey', widgets: 'duprey' })
  assert.equal(await widgetKeyFits({ baseURL: server, key: 'widgets' }, app), true)
  serve({ app: 'duprey', widgets: 'test-family' })
  assert.equal(await widgetKeyFits({ baseURL: server, key: 'widgets' }, app), false)
  serve({ app: 'duprey', widgets: 401 })
  assert.equal(await widgetKeyFits({ baseURL: server, key: 'widgets' }, app), false)
  assert.equal(await widgetKeyFits({ baseURL: 'http://10.0.0.5:8080/', key: 'widgets' }, app), false)
  assert.equal(await widgetKeyFits(null, app), false)
})

test("widgetKeyFits: keeps the key when it can't tell (an older server, or offline)", async () => {
  const app = { baseURL: server, key: 'app' }
  serve({ app: null, widgets: null })
  assert.equal(await widgetKeyFits({ baseURL: server, key: 'widgets' }, app), true)
  serve({ app: 'duprey', widgets: 503 })
  assert.equal(await widgetKeyFits({ baseURL: server, key: 'widgets' }, app), true)
})

test('watchKeyFits: replaces legacy shared keys and keys belonging to a different person', async () => {
  const { watchKeyFits } = await import('../src/api.ts')
  let owners: Record<string, string | null> = { app: 'm1', watch: 'shared' }
  globalThis.fetch = (async (_url: string, init: RequestInit) => {
    const key = String((init.headers as Record<string, string>).Authorization).replace('Bearer ', '')
    return new Response(JSON.stringify({ scope: key === 'app' ? 'admin' : 'display', owner: owners[key], householdId: 'demo-family' }))
  }) as typeof fetch
  const saved = { baseURL: server, key: 'watch' }, app = { baseURL: server, key: 'app' }
  assert.equal(await watchKeyFits(saved, app), false)
  owners.watch = 'm1'
  assert.equal(await watchKeyFits(saved, app), true)
  owners.app = 'm2'
  assert.equal(await watchKeyFits(saved, app), false)
  owners = { app: null, watch: 'shared' }
  assert.equal(await watchKeyFits(saved, app), true)
})

// Sign-out revokes the widgets' and Watch's keys after the phone has let go of them (src/session.ts):
// an unreachable server must not keep that request open for minutes.
test('revokeOwnKey gives up after 10 seconds', async (t) => {
  const { revokeOwnKey } = await import('../src/api.ts')
  t.mock.timers.enable({ apis: ['setTimeout'] })
  globalThis.fetch = ((_url: string, init: RequestInit) => new Promise((_, reject) => {
    init.signal?.addEventListener('abort', () => reject(new Error('aborted')))
  })) as typeof fetch
  const revoking = revokeOwnKey({ baseURL: server, key: 'widgets' })
  t.mock.timers.tick(10_000)
  await assert.rejects(revoking, /aborted/)
})
