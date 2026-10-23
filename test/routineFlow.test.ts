import { test } from 'node:test'
import assert from 'node:assert/strict'
import { RoutineFlow, type RoutineNative, type RoutineStatus } from '../src/routineFlow.ts'

const state = () => ({ enabled: true, appMode: 'selected', locked: true, checkedAt: new Date().toISOString(), validUntil: new Date(Date.now() + 3600000).toISOString() })
const packet = (n: number) => ({ data: btoa(`opaque-selection-${n}`), selectedApps: n, selectedCategories: 0, allowedApps: 1 })
function fixture() {
  const saved = new Map<string, any>(), reports: any[] = [], applied: any[] = [], imported: any[] = [], authorizations: string[] = []
  let status: RoutineStatus = { simulator: false, authorized: false, selected: 0, locked: false, memberId: '', appliedRevision: 0 }
  let pick = packet(2)
  const native: RoutineNative = {
    status: async () => ({ ...status }),
    authorize: async (id, server) => { authorizations.push(id); status = { ...status, authorized: true, memberId: id, server }; return { ...status } },
    choose: async () => pick,
    importSelection: async (id, server, data, revision) => { imported.push({ id, server, data, revision }); status = { ...status, memberId: id, server, appliedRevision: revision, hasAppChoices: true }; return { ...status } },
    apply: async json => { applied.push(JSON.parse(json)); status = { ...status, locked: JSON.parse(json).locked }; return { ...status } },
  }
  const flow = new RoutineFlow({ native, identity: async c => c.key === 'parent' ? { scope: 'admin', owner: null } : { scope: 'display', owner: c.key },
    request: async (_c, method, path, body?: any) => {
      const id = path.split('/')[2]
      if (path.endsWith('/apps')) {
        if (method === 'GET') return saved.get(id) ?? { revision: 0, data: null }
        const row = { ...body, revision: (saved.get(id)?.revision ?? 0) + 1 }; saved.set(id, row); return row
      }
      if (path.endsWith('/device')) { reports.push({ id, ...body }); return { ok: true } }
      return state()
    },
  })
  return { flow, native, saved, reports, applied, imported, authorizations, pick: (n: number) => { pick = packet(n) }, status: (next: Partial<RoutineStatus>) => { status = { ...status, ...next } } }
}

test('parent selection does not request child authorization or restrict the parent phone; choices stay per child', async () => {
  const f = fixture(); f.flow.setConnection({ baseURL: 'https://our-family.kinwall.family', key: 'parent' })
  const maya = await f.flow.choose('maya'); f.pick(4); await f.flow.choose('leo')
  assert.equal(f.saved.get('maya').selectedApps, 2)
  assert.equal(f.saved.get('leo').selectedApps, 4)
  assert.equal((maya as any).data, undefined, 'Apple tokens never reach the web bridge')
  assert.deepEqual(f.authorizations, [])
  assert.deepEqual(f.applied, [])
  assert.deepEqual(f.imported, [])
  await f.flow.sync('maya')
  assert.deepEqual(f.applied, [])
})

test('a paired child authorizes, receives only its own selection, applies the server decision and acknowledges it', async () => {
  const f = fixture(); const baseURL = 'https://our-family.kinwall.family'
  f.flow.setConnection({ baseURL, key: 'parent' }); await f.flow.choose('maya'); f.pick(4); await f.flow.choose('leo')
  f.flow.setConnection({ baseURL, key: 'maya' }); await f.flow.authorize('maya')
  assert.deepEqual(f.authorizations, ['maya'])
  assert.equal(f.imported[0].data, packet(2).data)
  assert.equal(f.imported[0].id, 'maya')
  assert.equal(f.applied[0].locked, true)
  assert.equal(f.reports.at(-1).appliedRevision, 1)
  await assert.rejects(f.flow.choose('leo'), /grown-up/)
  await assert.rejects(f.flow.authorize('leo'), /own/)
  await assert.rejects(f.flow.sync('leo'), /own/)
})

test('unauthorized child and a newly authorized child without saved app choices do not claim enforcement', async () => {
  const f = fixture(); f.flow.setConnection({ baseURL: 'https://our-family.kinwall.family', key: 'maya' })
  await f.flow.sync('maya')
  assert.equal(f.reports.at(-1).authorized, false)
  assert.equal(f.applied.length, 0)
  const status = await f.flow.authorize('maya')
  assert.equal(status.awaitingSelection, true)
  assert.equal(f.applied.length, 0)
})

test('a parent changing sign-in while the picker is open cannot save into either family', async () => {
  const f = fixture(); f.flow.setConnection({ baseURL: 'https://our-family.kinwall.family', key: 'parent' })
  let finish!: (value: ReturnType<typeof packet>) => void
  let opened!: () => void
  const ready = new Promise<void>(r => { opened = r })
  f.native.choose = async () => { opened(); return new Promise(r => { finish = r }) }
  const pending = f.flow.choose('maya'); await ready
  f.flow.setConnection({ baseURL: 'https://other.kinwall.family', key: 'parent' }); finish(packet(9))
  await assert.rejects(pending, /Sign-in changed/)
  assert.equal(f.saved.size, 0)
})

test('child binding prevents another family or child from applying saved tokens', async () => {
  const f = fixture(); f.status({ authorized: true, memberId: 'leo', server: 'https://our-family.kinwall.family' })
  f.flow.setConnection({ baseURL: 'https://our-family.kinwall.family', key: 'maya' })
  await assert.rejects(f.flow.sync('maya'), /different child/)
  f.status({ memberId: 'maya', server: 'https://other.kinwall.family' })
  await assert.rejects(f.flow.sync('maya'), /different family/)
  assert.equal(f.applied.length, 0)
})

test('a concurrent sync request for another child is checked after the active request', async () => {
  const f = fixture(); f.flow.setConnection({ baseURL: 'https://our-family.kinwall.family', key: 'maya' })
  let ready!: () => void, finish!: () => void
  const started = new Promise<void>(resolve => { ready = resolve })
  const original = f.native.status
  f.native.status = async () => { ready(); await new Promise<void>(resolve => { finish = resolve }); f.native.status = original; return original() }
  const first = f.flow.sync('maya'); await started
  const other = f.flow.sync('leo')
  const rejected = assert.rejects(other, /own routine/)
  finish(); await first; await rejected
})

test('cancelling the guardian picker preserves saved choices', async () => {
  const f = fixture(); f.flow.setConnection({ baseURL: 'https://our-family.kinwall.family', key: 'parent' })
  await f.flow.choose('maya')
  const before = structuredClone(f.saved.get('maya'))
  f.native.choose = async () => ({ cancelled: true })
  assert.equal((await f.flow.choose('maya')).cancelled, true)
  assert.deepEqual(f.saved.get('maya'), before)
})
