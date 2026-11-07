import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, existsSync, statSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const fake = { project_info: { project_id: 'demo-project', project_number: '123456' }, client: [{
  client_info: { mobilesdk_app_id: '1:123456:android:fake', android_client_info: { package_name: 'family.kinwall.app' } },
  api_key: [{ current_key: 'fake-client-api-key' }],
}] }
function run(value?: string) {
  const dir = mkdtempSync(join(tmpdir(), 'kinwall-firebase-ci-'))
  const output = join(dir, 'google-services.json'), envFile = join(dir, 'env')
  const result = spawnSync(process.execPath, ['scripts/android-firebase-ci.mjs'], {
    env: { PATH: process.env.PATH, RUNNER_TEMP: dir, GITHUB_ENV: envFile, ...(value === undefined ? {} : { KINWALL_GOOGLE_SERVICES_JSON: value }) }, encoding: 'utf8',
  })
  return { ...result, output, envFile, clean: () => rmSync(dir, { recursive: true, force: true }) }
}
test('Android CI without Firebase config keeps the local-reminder build', () => {
  const r = run()
  try { assert.equal(r.status, 0); assert.equal(existsSync(r.output), false); assert.equal(existsSync(r.envFile), false) }
  finally { r.clean() }
})
test('Android CI writes only client config privately and exports its path for prebuild and bundling', () => {
  const value = JSON.stringify(fake), r = run(value)
  try {
    assert.equal(r.status, 0, r.stderr)
    assert.deepEqual(JSON.parse(readFileSync(r.output, 'utf8')), fake)
    assert.equal(statSync(r.output).mode & 0o777, 0o600)
    assert.equal(readFileSync(r.envFile, 'utf8'), `KINWALL_GOOGLE_SERVICES_FILE=${r.output}\n`)
    assert.equal(r.stdout.includes('fake-client-api-key'), false)
    assert.equal(r.stderr.includes('fake-client-api-key'), false)
  } finally { r.clean() }
})
test('Android CI rejects malformed config, wrong app and server credentials without logging content', () => {
  for (const value of ['private-data-invalid-json', JSON.stringify({ ...fake, client: [] }),
    JSON.stringify({ ...fake, client: [{ client_info: { android_client_info: { package_name: 'other.app' } } }] }),
    JSON.stringify({ ...fake, private_key: 'fake-private-key-do-not-log' }),
    JSON.stringify({ ...fake, project_info: { project_id: 'demo-project' } }),
  ]) {
    const r = run(value)
    try {
      assert.equal(r.status, 1)
      assert.match(r.stderr, /Invalid Firebase Android client configuration/)
      assert.equal(existsSync(r.output), false)
      assert.equal(existsSync(r.envFile), false)
      assert.equal(r.stderr.includes(value), false)
      assert.doesNotMatch(r.stdout + r.stderr, /fake-private-key-do-not-log|private-data-invalid-json/)
    } finally { r.clean() }
  }
})
