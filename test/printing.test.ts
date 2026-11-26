import { test } from 'node:test'
import assert from 'node:assert/strict'
import { bridgeMessage } from '../src/bridge.ts'
import { printAvailable, routePrint } from '../src/printing.ts'

const server = 'https://example.kinwall.family'

test('print is advertised only by native builds with printing support', () => {
  assert.equal(printAvailable(null), false)
  assert.equal(printAvailable({}), false)
  assert.equal(printAvailable({ printSupported: () => true }), false)
  assert.equal(printAvailable({ printSupported: () => false, printCurrentPage: async () => {} }), false)
  assert.equal(printAvailable({ printSupported: () => true, printCurrentPage: async () => {} }), true)
})

test('only trusted print messages reach the current native view, with a safe title fallback', async () => {
  const jobs: [number, string][] = []
  const native = { printSupported: () => true, printCurrentPage: async (tag: number, title: string) => { jobs.push([tag, title]) } }
  const receive = (data: unknown, page = server) => routePrint(bridgeMessage(JSON.stringify(data), 'launch', page, server), 42, native)
  assert.equal(await receive({ type: 'print', title: 'Tacos', nonce: 'launch' }), true)
  for (const title of [undefined, null, 7, '', '  ']) {
    assert.equal(await receive({ type: 'print', title, nonce: 'launch' }), true)
  }
  assert.deepEqual(jobs, [[42, 'Tacos'], ...Array.from({ length: 5 }, () => [42, 'Kinwall recipe'])])
  const count = jobs.length
  for (const data of [{ type: 'print' }, { type: 'print', nonce: 'old' }, { type: 'unknown', nonce: 'launch' }]) {
    assert.equal(await receive(data), false)
  }
  assert.equal(await receive({ type: 'print', nonce: 'launch' }, `${server}/plugins/x`), false)
  assert.equal(await receive({ type: 'print', nonce: 'launch' }, 'https://elsewhere.example'), false)
  assert.equal(await routePrint({ type: 'print' }, null, native), false)
  assert.equal(await routePrint({ type: 'print' }, 42, {}), false)
  assert.equal(jobs.length, count)
})
