import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { appendFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

/** A fresh runner must reuse a private-key identity, never ask Apple for another certificate. */
export function chooseSigningIdentity(identities, subject, team) {
  if (!/^[A-Z0-9]{10}$/.test(team) || !new RegExp(`(?:^|,)OU=${team}(?:,|$)`).test(subject.replace(/^subject=\s*/, ''))) throw new Error('The signing certificate must belong to the configured Apple team.')
  const matches = [...identities.matchAll(/^\s*\d+\) ([A-Fa-f0-9]{40}) "Apple Development:[^"\n]+"\s*$/gm)]
  if (matches.length !== 1) throw new Error('Import exactly one valid Apple Development identity, including its private key.')
  return matches[0][1].toUpperCase()
}

function install() {
  const { APPLE_SIGNING_P12_BASE64: encoded, APPLE_SIGNING_P12_PASSWORD: password, TEAM: team, RUNNER_TEMP: temp, GITHUB_ENV: output } = process.env
  if (!encoded || !password || !temp || !output || !team) throw new Error('Configure the reusable signing P12 and password in the release environment before running TestFlight.')
  const normalized = encoded.replace(/\s/g, '')
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized) || normalized.length % 4) throw new Error('The signing P12 must be base64 encoded.')
  const certificatePath = join(temp, 'kinwall-signing.p12'), keychainPath = join(temp, 'kinwall-signing.keychain-db')
  const keychainPassword = randomBytes(32).toString('hex')
  // Never include a failed command or its arguments in logs: those can contain passwords.
  const run = (command, args, input) => {
    try { return execFileSync(command, args, { input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }) }
    catch { throw new Error('Could not install or validate the reusable signing identity. Check the P12, password, team and certificate expiration.') }
  }
  let installed = false
  try {
    writeFileSync(certificatePath, Buffer.from(normalized, 'base64'), { mode: 0o600, flag: 'wx' })
    run('security', ['create-keychain', '-p', keychainPassword, keychainPath])
    run('security', ['set-keychain-settings', '-lut', '21600', keychainPath])
    run('security', ['unlock-keychain', '-p', keychainPassword, keychainPath])
    run('security', ['import', certificatePath, '-P', password, '-t', 'cert', '-f', 'pkcs12', '-k', keychainPath, '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'])
    run('security', ['set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', keychainPassword, keychainPath])
    run('security', ['list-keychains', '-d', 'user', '-s', keychainPath])
    const identities = run('security', ['find-identity', '-v', '-p', 'codesigning', keychainPath])
    const certificate = run('security', ['find-certificate', '-c', 'Apple Development:', '-p', keychainPath])
    const subject = run('openssl', ['x509', '-noout', '-subject', '-nameopt', 'RFC2253'], certificate)
    const identity = chooseSigningIdentity(identities, subject.trim(), team)
    appendFileSync(output, `APPLE_SIGNING_IDENTITY=${identity}\n`)
    installed = true
    console.log('Reusable development signing identity validated in the isolated archive keychain.')
  } finally {
    rmSync(certificatePath, { force: true })
    if (!installed) { try { execFileSync('security', ['delete-keychain', keychainPath], { stdio: 'ignore' }) } catch { /* cleanup only */ } }
  }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try { install() }
  catch (error) { console.error(error.message); process.exitCode = 1 }
}
