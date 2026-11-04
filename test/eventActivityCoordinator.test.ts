import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

test('native event activities: serialized starts and deterministic duplicate cleanup', { skip: process.platform !== 'darwin' }, () => {
 const dir=mkdtempSync(join(tmpdir(),'kinwall-event-coordinator-'))
 try {
  const source=decodeURIComponent(new URL('../modules/kinwall-native/ios/EventActivityCoordinator.swift',import.meta.url).pathname)
  const checks=decodeURIComponent(new URL('./swift/event-activity-coordinator/main.swift',import.meta.url).pathname)
  const binary=join(dir,'event-coordinator')
  execFileSync('xcrun',['swiftc','-parse-as-library','-module-cache-path',join(dir,'cache'),source,checks,'-o',binary],{timeout:120000,stdio:'pipe'})
  assert.match(execFileSync(binary,{encoding:'utf8'}),/event activity checks passed/)
 } finally {rmSync(dir,{recursive:true,force:true})}
})
