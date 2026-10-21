import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const require = createRequire(import.meta.url)

test('Watch target supplies an opaque 1024px icon for Apple target generation', () => {
  const target = require('../targets/watch/expo-target.config.js')
  // apple-targets only sets ASSETCATALOG_COMPILER_APPICON_NAME when icon is supplied.
  // An existing AppIcon.appiconset alone builds successfully but fails App Store validation.
  assert.equal(typeof target.icon, 'string', 'declare the Watch app icon in the target config')
  const png = readFileSync(resolve('targets/watch', target.icon))
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a')
  assert.equal(png.readUInt32BE(16), 1024)
  assert.equal(png.readUInt32BE(20), 1024)
  assert.equal(png[25], 2, 'App Store icon must be RGB without an alpha channel')
})
