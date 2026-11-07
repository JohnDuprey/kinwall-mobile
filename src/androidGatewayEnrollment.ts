import { GatewayHTTPError } from './gatewayEnrollment.ts'

export type AndroidGatewayInput = { server: string; token: string; kind: 'android-alert' }
export type AndroidGatewayCredential = AndroidGatewayInput & { credential: string; expiresAt: number }
export type AndroidGatewayState = { registrations: AndroidGatewayCredential[]; pending: AndroidGatewayCredential[] }
type Dependencies = {
  supported(): boolean
  publicKey(): Promise<{ publicKey: string; keyId: string }>
  hash(text: string, encoding: 'hex' | 'base64url'): Promise<string>
  proof(clientData: string): Promise<{ integrityToken: string; signature: string }>
  load(): Promise<AndroidGatewayState | null>
  save(state: AndroidGatewayState): Promise<void>
  request(path: string, body?: unknown, method?: 'POST' | 'DELETE', credential?: string): Promise<unknown>
  now?(): number
}
const object = (v: unknown): Record<string, unknown> => v && typeof v === 'object' ? v as Record<string, unknown> : {}
const credentialPattern = /^android-v1\.([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\.[a-f0-9]{64}$/
const same = (a: AndroidGatewayInput, b: AndroidGatewayInput) => a.server === b.server && a.token === b.token && a.kind === b.kind
function normalize(input: AndroidGatewayInput): AndroidGatewayInput {
  const url = new URL(input.server)
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.origin === 'null'
    || input.kind !== 'android-alert' || typeof input.token !== 'string' || !/^[\x21-\x7e]{1,4096}$/.test(input.token)) throw new Error('Invalid Android device registration')
  return { server: url.origin, token: input.token, kind: 'android-alert' }
}

/** Separate protocol/storage from Apple. The shell owns this client; nothing is exposed to the page.
 * Serialize enrollment, rotation and durable cleanup so sign-out cannot miss a late capability. */
export class AndroidGatewayEnrollmentClient {
  private deps: Dependencies
  private queue: Promise<unknown> = Promise.resolve()
  constructor(deps: Dependencies) { this.deps = deps }
  private now() { return this.deps.now?.() ?? Date.now() }
  private run<T>(work: () => Promise<T>): Promise<T> {
    const next = this.queue.catch(() => {}).then(work); this.queue = next; return next
  }
  private async load(): Promise<AndroidGatewayState> {
    const state = await this.deps.load()
    const valid = (value: unknown): value is AndroidGatewayCredential => {
      const r = object(value)
      try { const input = normalize(r as AndroidGatewayCredential)
        return input.server === r.server && typeof r.credential === 'string' && credentialPattern.test(r.credential)
          && Number.isSafeInteger(r.expiresAt) && (r.expiresAt as number) > this.now()
      } catch { return false }
    }
    return { registrations: Array.isArray(state?.registrations) ? state.registrations.filter(valid) : [],
      pending: Array.isArray(state?.pending) ? state.pending.filter(valid) : [] }
  }
  private retire(state: AndroidGatewayState, entries: AndroidGatewayCredential[]) {
    const credentials = new Set(entries.map(e => e.credential))
    state.registrations = state.registrations.filter(e => !credentials.has(e.credential))
    for (const entry of entries) if (!state.pending.some(r => r.credential === entry.credential)) state.pending.push(entry)
  }
  private async flush(state: AndroidGatewayState) {
    for (const entry of state.pending.slice(0, 3)) {
      try {
        const result = object(await this.deps.request('/v1/android/registration', undefined, 'DELETE', entry.credential))
        if (result.revoked !== true) continue
      } catch (error) { if (!(error instanceof GatewayHTTPError && error.status === 401)) continue }
      state.pending = state.pending.filter(r => r.credential !== entry.credential)
      await this.deps.save(state)
    }
  }
  get(input: AndroidGatewayInput): Promise<AndroidGatewayCredential> {
    return this.run(async () => {
      const registration = normalize(input), state = await this.load()
      // Check build support even with cached state: a restored credential cannot enable a debug build.
      if (!this.deps.supported()) throw new Error('Android app verification unavailable')
      const cached = state.registrations.find(r => same(r, registration) && r.expiresAt > this.now() + 300000)
      if (cached) return cached
      await this.flush(state)
      const key = await this.deps.publicKey()
      if (!key.publicKey || !/^[a-f0-9]{64}$/.test(key.keyId)) throw new Error('Invalid Android verification key')
      const challenge = object(await this.deps.request('/v1/android/enrollment/challenge', { publicKey: key.publicKey, registration }))
      if (typeof challenge.id !== 'string' || !challenge.id || challenge.id.length > 200 || typeof challenge.clientData !== 'string'
        || challenge.clientData.length > 4096 || !Number.isSafeInteger(challenge.expiresAt) || (challenge.expiresAt as number) <= this.now()
        || (challenge.expiresAt as number) > this.now() + 300000) throw new Error('Invalid Android enrollment challenge')
      let data: Record<string, unknown>
      try { data = object(JSON.parse(challenge.clientData)) } catch { throw new Error('Invalid Android enrollment challenge') }
      const expected = JSON.stringify({ protocol: 'kinwall-android-push-v1', challenge: data.challenge, keyId: key.keyId,
        tokenHash: await this.deps.hash(registration.token, 'hex'), server: registration.server, kind: registration.kind })
      if (typeof data.challenge !== 'string' || !/^[a-f0-9]{64}$/.test(data.challenge) || expected !== challenge.clientData
        || challenge.requestHash !== await this.deps.hash(expected, 'base64url')) throw new Error('Android enrollment challenge changed')
      const proof = await this.deps.proof(challenge.clientData)
      const result = object(await this.deps.request('/v1/android/enrollment/register', {
        publicKey: key.publicKey, registration, challengeId: challenge.id, integrityToken: proof.integrityToken, signature: proof.signature,
      }))
      const match = typeof result.credential === 'string' ? credentialPattern.exec(result.credential) : null
      if (!match || result.id !== match[1] || !Number.isSafeInteger(result.expiresAt) || (result.expiresAt as number) <= this.now()
        || (result.expiresAt as number) > this.now() + 30 * 86400000) throw new Error('Invalid Android gateway registration')
      const entry: AndroidGatewayCredential = { ...registration, credential: result.credential as string, expiresAt: result.expiresAt as number }
      const old = state.registrations.filter(r => r.server === registration.server)
      // Renewal rotates a bearer on the same row; deleting its old bearer could revoke the new row.
      this.retire(state, old.filter(r => credentialPattern.exec(r.credential)?.[1] !== result.id))
      state.registrations = state.registrations.filter(r => !old.includes(r)); state.registrations.push(entry)
      await this.deps.save(state); await this.flush(state)
      return entry
    })
  }
  revoke(input: AndroidGatewayInput): Promise<void> {
    return this.run(async () => {
      const registration = normalize(input), state = await this.load()
      this.retire(state, state.registrations.filter(r => same(r, registration)))
      await this.deps.save(state); await this.flush(state)
    })
  }
  revokeServer(server: string): Promise<void> {
    return this.run(async () => {
      const origin = new URL(server).origin, state = await this.load()
      this.retire(state, state.registrations.filter(r => r.server === origin))
      await this.deps.save(state); await this.flush(state)
    })
  }
  flushRevocations(): Promise<void> { return this.run(async () => { await this.flush(await this.load()) }) }
}
