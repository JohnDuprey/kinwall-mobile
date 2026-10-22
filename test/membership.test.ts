import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const { membership } = require('../plugins/membership.js')

test('membership features: release builds opt into production APNs and hosted associated domains', () => {
  const release = membership({ KINWALL_PUSH: '1', KINWALL_APNS_ENV: 'production', KINWALL_ASSOCIATED_DOMAINS: '1' })
  assert.equal(release.push, true)
  assert.equal(release.appAttest, true)
  assert.equal(release.timeSensitive, true)
  assert.equal(release.apnsEnvironment, 'production')
  assert.ok(release.domains.includes('webcredentials:kinwall.family'))
  assert.ok(release.domains.includes('applinks:*.kinwall.family'))
  const local = membership({})
  assert.equal(local.push, false); assert.equal(local.timeSensitive, false)
  assert.equal(local.appAttest, false)
  assert.deepEqual(local.domains, [])
  assert.equal(membership({ KINWALL_PUSH: '1' }).apnsEnvironment, 'development')
  assert.throws(() => membership({ KINWALL_PUSH: '1', KINWALL_APNS_ENV: 'typo' }))
})
