import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createLoadRecovery } from '../src/loadRecovery.ts'

function setup(platform = 'ios') {
  let foreground = true
  const timers = new Map<number, () => void>()
  let next = 0
  let restarts = 0
  const errors: string[] = []
  const recovery = createLoadRecovery({
    platform,
    active: () => foreground,
    restart: () => { restarts++ },
    fail: (message) => errors.push(message),
    schedule: (run) => { timers.set(++next, run); return next },
    cancel: (id) => { timers.delete(id) },
  })
  return { recovery, errors, timers, restarts: () => restarts, background: () => { foreground = false }, foreground: () => { foreground = true; recovery.resume() }, run: () => { const callbacks = [...timers.values()]; timers.clear(); callbacks.forEach(run => run()) } }
}

const interrupted = { domain: 'NSURLErrorDomain', code: -1005, description: 'The network connection was lost.' }

test('a brief startup connection failure retries twice before showing the error', () => {
  const s = setup()
  s.recovery.failed(interrupted)
  assert.deepEqual(s.errors, [])
  s.run()
  assert.equal(s.restarts(), 1)
  s.recovery.failed(interrupted)
  s.run()
  assert.equal(s.restarts(), 2)
  s.recovery.failed(interrupted)
  assert.deepEqual(s.errors, [interrupted.description])
  assert.equal(s.timers.size, 0)
})

test('a successful load gives the next connection interruption its own retry budget', () => {
  const s = setup()
  s.recovery.failed(interrupted); s.run()
  s.recovery.loaded()
  s.recovery.failed(interrupted); s.run()
  s.recovery.failed(interrupted); s.run()
  assert.equal(s.restarts(), 3)
  assert.deepEqual(s.errors, [])
})

test('load events around an error do not reset retries before the page renders', () => {
  const s = setup()
  // iOS calls onLoadEnd after onError; Android also emits onLoad before it.
  // Wait for the rendered page to confirm success before calling loaded().
  s.recovery.failed(interrupted)
  s.recovery.resume()
  assert.equal(s.restarts(), 1)
  s.recovery.failed(interrupted); s.run()
  s.recovery.failed(interrupted)
  assert.equal(s.errors.length, 1)
})

test('background failures wait until the app comes forward', () => {
  const s = setup()
  s.background()
  s.recovery.failed(interrupted); s.run()
  assert.equal(s.restarts(), 0)
  s.foreground()
  assert.equal(s.restarts(), 1)
  s.run()
  assert.equal(s.restarts(), 1)
})

test('success, manual retry and disposal cancel pending retries', () => {
  for (const action of ['loaded', 'retry', 'dispose'] as const) {
    const s = setup()
    s.recovery.failed(interrupted)
    s.recovery[action]()
    s.run()
    assert.equal(s.restarts(), action === 'retry' ? 1 : 0)
    assert.equal(s.timers.size, 0)
  }
})

test('certificate errors and other non-network failures stay visible without retrying', () => {
  for (const [platform, error] of [
    ['ios', { domain: 'NSURLErrorDomain', code: -1202, description: 'Untrusted certificate' }],
    ['ios', { domain: 'WebKitErrorDomain', code: -1005, description: 'Other failure' }],
    ['android', { code: -11, description: 'SSL handshake failed' }],
  ] as const) {
    const s = setup(platform)
    s.recovery.failed(error)
    s.run()
    assert.deepEqual(s.errors, [error.description])
    assert.equal(s.restarts(), 0)
  }
})

test('Android connection errors also retry, and manual retry starts a fresh budget', () => {
  const s = setup('android')
  const error = { code: -2, description: 'net::ERR_NAME_NOT_RESOLVED' }
  s.recovery.failed(error); s.run()
  s.recovery.failed(error); s.run()
  s.recovery.failed(error)
  s.recovery.retry()
  s.recovery.failed(error); s.run()
  assert.equal(s.restarts(), 4)
})

test('page probes ignore old replies and timers after a page replacement', async () => {
  const { createPageProbe } = await import('../src/loadRecovery.ts')
  const timers: (() => void)[] = []
  const sent: number[] = []
  let restarts = 0
  let active = true
  const probe = createPageProbe({ active: () => active, restart: () => { restarts++ }, send: (id) => sent.push(id), schedule: (run) => { timers.push(run); return timers.length }, cancel: () => {} })
  probe.start()
  probe.cancel()
  probe.start()
  assert.equal(probe.answer(sent[0]), false)
  timers[0]!()
  assert.equal(restarts, 0)
  assert.equal(probe.answer(sent[1]), true)
  timers[1]!()
  assert.equal(restarts, 0)
  probe.start()
  active = false
  timers[2]!()
  assert.equal(restarts, 0)
  active = true
  probe.start()
  timers[3]!()
  assert.equal(restarts, 1)
})
