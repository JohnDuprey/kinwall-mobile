import { test } from 'node:test'
import assert from 'node:assert/strict'
import { atMostEvery } from '../src/throttle.ts'

// iOS can report the app active again every few seconds; on 2026-11-08 one phone re-ran its resume
// refresh (push, reminders, widgets, Watch) ~35 times in two minutes. Resume work runs at most once a minute.
test('atMostEvery runs at once, then not again until the interval has passed', () => {
  let now = 0, runs = 0
  const resume = atMostEvery(60_000, () => { runs++ }, () => now)
  resume(); resume()
  now = 59_999; resume()
  assert.equal(runs, 1)
  now = 60_000; resume()
  assert.equal(runs, 2)
})
