import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const config = require('../app.config.js')
test('Firebase config is opt-in and preserves build numbers, signing and app identity', () => {
  const previous = process.env.KINWALL_GOOGLE_SERVICES_FILE
  const build = process.env.KINWALL_BUILD_NUMBER
  try {
    delete process.env.KINWALL_GOOGLE_SERVICES_FILE
    process.env.KINWALL_BUILD_NUMBER = '10203'
    const original = { android: { package: 'family.kinwall.app' }, ios: { bundleIdentifier: 'family.kinwall.app' }, extra: { example: true } }
    const off = config({ config: original })
    assert.equal(off.android.googleServicesFile, undefined)
    assert.notEqual(off.extra?.androidNativePush, true)
    process.env.KINWALL_GOOGLE_SERVICES_FILE = '/tmp/fake-firebase-config.json'
    const on = config({ config: original })
    assert.equal(on.android.googleServicesFile, '/tmp/fake-firebase-config.json')
    assert.equal(on.extra.androidNativePush, true)
    assert.equal(on.extra.example, true)
    assert.equal(on.android.package, 'family.kinwall.app')
    assert.equal(on.ios.bundleIdentifier, 'family.kinwall.app')
    assert.equal(on.android.versionCode, 10203)
    assert.equal(on.ios.buildNumber, '10203')
  } finally {
    if (previous === undefined) delete process.env.KINWALL_GOOGLE_SERVICES_FILE; else process.env.KINWALL_GOOGLE_SERVICES_FILE = previous
    if (build === undefined) delete process.env.KINWALL_BUILD_NUMBER; else process.env.KINWALL_BUILD_NUMBER = build
  }
})
