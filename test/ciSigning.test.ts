import { test } from 'node:test'
import assert from 'node:assert/strict'
import { chooseSigningIdentity } from '../scripts/ci-signing.mjs'
const sha = 'A'.repeat(40)
const identities = `  1) ${sha} "Apple Development: Demo Parent (DEMOUSER)"\n     1 valid identities found`
const subject = 'subject=UID=DEMOUSER,CN=Apple Development: Demo Parent (DEMOUSER),OU=PPVX64R65G,O=Demo Parent,C=US'
test('CI selects an existing development identity only for the configured team', () => {
  assert.equal(chooseSigningIdentity(identities, subject, 'PPVX64R65G'), sha)
  assert.throws(() => chooseSigningIdentity(identities, subject, 'OTHERTEAM1'), /team/)
})
test('CI refuses missing, expired, ambiguous and distribution-only identities', () => {
  assert.throws(() => chooseSigningIdentity('0 valid identities found', subject, 'PPVX64R65G'), /one valid Apple Development/)
  assert.throws(() => chooseSigningIdentity(identities + `\n  2) ${'B'.repeat(40)} "Apple Development: Other"`, subject, 'PPVX64R65G'), /one valid Apple Development/)
  assert.throws(() => chooseSigningIdentity(identities.replace('Apple Development:', 'Apple Distribution:'), subject, 'PPVX64R65G'), /one valid Apple Development/)
  assert.throws(() => chooseSigningIdentity(identities, subject, ''), /team/)
})

test('missing reusable signing secrets fail before accessing a keychain or Apple', async () => {
  const { spawnSync } = await import('node:child_process')
  const result = spawnSync(process.execPath, ['scripts/ci-signing.mjs'], { cwd: new URL('..', import.meta.url), env: { PATH: '' }, encoding: 'utf8' })
  assert.equal(result.status, 1)
  assert.match(result.stderr, /Configure the reusable signing P12/)
  assert.equal(result.stdout, '')
})
