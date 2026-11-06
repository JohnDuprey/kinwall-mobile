import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

test('native cooking timer pause, resume, stale payloads, ranges and persistence', { skip: process.platform !== 'darwin' }, () => {
 const dir=mkdtempSync(join(tmpdir(),'kinwall-cooking-controls-'))
 try {
  const source=decodeURIComponent(new URL('../modules/kinwall-native/ios/CookingTimerState.swift',import.meta.url).pathname)
  const checks=decodeURIComponent(new URL('./swift/cooking-timer-controls/main.swift',import.meta.url).pathname)
  const binary=join(dir,'cooking-controls')
  execFileSync('xcrun',['swiftc','-parse-as-library','-module-cache-path',join(dir,'cache'),source,checks,'-o',binary],{timeout:120000,stdio:'pipe'})
  assert.match(execFileSync(binary,{encoding:'utf8'}),/cooking timer checks passed/)
 } finally {rmSync(dir,{recursive:true,force:true})}
})
