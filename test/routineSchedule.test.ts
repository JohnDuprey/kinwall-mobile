import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

test('native routine schedule: daily reset, overrides, timezone and expired grants', { skip: process.platform !== 'darwin' }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'kinwall-routine-schedule-'))
  try {
    const core = new URL('../modules/kinwall-native/ios/RoutineSchedule.swift', import.meta.url).pathname
    const checks = new URL('./swift/routine-schedule/main.swift', import.meta.url).pathname
    const binary = join(dir, 'routine-schedule')
    execFileSync('xcrun', ['swiftc', '-module-cache-path', join(dir, 'cache'), decodeURIComponent(core), decodeURIComponent(checks), '-o', binary], { timeout: 120000, stdio: 'pipe' })
    assert.match(execFileSync(binary, { encoding: 'utf8' }), /25 checks passed/)
  } finally { rmSync(dir, { recursive: true, force: true }) }
})
