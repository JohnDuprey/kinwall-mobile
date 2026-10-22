export type GatewayKind = 'alert' | 'liveactivity-start' | 'liveactivity-update'
export type GatewayInput = { server: string; token: string; kind: GatewayKind }
export type GatewayCredential = GatewayInput & { credential: string; expiresAt: number }
export type GatewayState = { keyId: string | null; verified: boolean; registrations: GatewayCredential[]; pending: GatewayCredential[] }
type Dependencies = {
  supported(): boolean
  generateKey(): Promise<string>
  attestKey(key: string, challenge: string): Promise<string>
  assertion(key: string, clientData: string): Promise<string>
  load(): Promise<GatewayState | null>
  save(state: GatewayState): Promise<void>
  request(path: string, body?: unknown, method?: 'POST' | 'DELETE', credential?: string): Promise<unknown>
  now?(): number
}
export class GatewayHTTPError extends Error {
  status: number
  constructor(status: number) { super('Push gateway request failed'); this.status = status }
}
const empty = (): GatewayState => ({ keyId: null, verified: false, registrations: [], pending: [] })
const object = (value: unknown): Record<string, unknown> => value && typeof value === 'object' ? value as Record<string, unknown> : {}
const same = (a: GatewayInput, b: GatewayInput) => a.server === b.server && a.kind === b.kind && a.token === b.token
const credentialPattern = /^[a-f0-9-]{36}\.[a-f0-9]{64}$/
const valid = (r: GatewayCredential) => r && typeof r.server === 'string' && typeof r.token === 'string' && ['alert','liveactivity-start','liveactivity-update'].includes(r.kind)
  && typeof r.credential === 'string' && credentialPattern.test(r.credential) && Number.isSafeInteger(r.expiresAt)

/** Serializing the complete handshake keeps App Attest assertion counters in request order. */
export class GatewayEnrollmentClient {
  private deps: Dependencies
  private queue: Promise<unknown> = Promise.resolve()
  constructor(deps: Dependencies) { this.deps = deps }
  private now() { return this.deps.now?.() ?? Date.now() }
  private run<T>(work: () => Promise<T>): Promise<T> {
    const next = this.queue.catch(() => {}).then(work)
    this.queue = next
    return next
  }
  private async load(): Promise<GatewayState> {
    const state = await this.deps.load()
    if (!state || !Array.isArray(state.registrations) || !Array.isArray(state.pending)) return empty()
    return { keyId: typeof state.keyId === 'string' ? state.keyId : null, verified: state.verified === true,
      registrations: state.registrations.filter(r => valid(r) && r.expiresAt > this.now()),
      pending: state.pending.filter(r => valid(r) && r.expiresAt > this.now()) }
  }
  private async flush(state: GatewayState) {
    // Keep failures in secure storage, and bound work on any one foreground/background refresh.
    for (const entry of state.pending.slice(0, 3)) {
      try { await this.deps.request('/v1/registration', undefined, 'DELETE', entry.credential) }
      catch (error) { if (!(error instanceof GatewayHTTPError && error.status === 401)) continue }
      state.pending = state.pending.filter(r => r.credential !== entry.credential)
      await this.deps.save(state)
    }
  }
  private retire(state: GatewayState, entries: GatewayCredential[]) {
    const retiring = new Set(entries.map(e => e.credential))
    state.registrations = state.registrations.filter(e => !retiring.has(e.credential))
    for (const entry of entries) if (!state.pending.some(r => r.credential === entry.credential)) state.pending.push(entry)
  }
  private async key(state: GatewayState): Promise<string> {
    if (!state.keyId) { state.keyId = await this.deps.generateKey(); state.verified = false; await this.deps.save(state) }
    if (!state.verified) {
      const challenge = object(await this.deps.request('/v1/enrollment/challenge', { keyId: state.keyId }))
      if (typeof challenge.id !== 'string' || typeof challenge.challenge !== 'string' || !/^[a-f0-9]{64}$/.test(challenge.challenge)
        || typeof challenge.expiresAt !== 'number' || challenge.expiresAt <= this.now()) throw new Error('Invalid enrollment challenge')
      const attestation = await this.deps.attestKey(state.keyId, challenge.challenge)
      const result = object(await this.deps.request('/v1/enrollment/attest', { keyId: state.keyId, challengeId: challenge.id, attestation }))
      if (result.verified !== true) throw new Error('App verification failed')
      state.verified = true; await this.deps.save(state)
    }
    return state.keyId
  }
  get(input: GatewayInput): Promise<GatewayCredential> {
    return this.run(async () => {
      const url = new URL(input.server)
      if (!['http:','https:'].includes(url.protocol) || url.username || url.password || !/^[a-f0-9]{16,400}$/i.test(input.token)) throw new Error('Invalid device registration')
      const registration = { token: input.token.toLowerCase(), server: url.origin, kind: input.kind }
      const state = await this.load()
      const cached = state.registrations.find(r => same(r, registration) && r.expiresAt > this.now() + 5 * 60000)
      if (cached) return cached
      if (!this.deps.supported()) throw new Error('App verification unavailable')
      // Leave headroom under the gateway's per-installation cap. Completed activity update
      // tokens can otherwise accumulate for twelve hours while the app is actively used.
      const excess = Math.max(0, state.registrations.length - 23)
      if (excess) {
        this.retire(state, state.registrations.filter(r => r.kind === 'liveactivity-update' && !same(r, registration)).slice(0, excess))
        await this.deps.save(state)
      }
      await this.flush(state)
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const keyId = await this.key(state)
          const challenge = object(await this.deps.request('/v1/enrollment/registration/challenge', { keyId, registration }))
          if (typeof challenge.id !== 'string' || typeof challenge.challenge !== 'string' || !/^[a-f0-9]{64}$/.test(challenge.challenge)
            || typeof challenge.expiresAt !== 'number' || challenge.expiresAt <= this.now()) throw new Error('Invalid registration challenge')
          const clientData = JSON.stringify({ challenge: challenge.challenge, keyId, ...registration })
          if (challenge.clientData !== clientData) throw new Error('Registration challenge changed')
          const assertion = await this.deps.assertion(keyId, clientData)
          const result = object(await this.deps.request('/v1/enrollment/register', { keyId, challengeId: challenge.id, registration, assertion }))
          if (typeof result.credential !== 'string' || !credentialPattern.test(result.credential) || typeof result.expiresAt !== 'number'
            || !Number.isSafeInteger(result.expiresAt) || result.expiresAt <= this.now() || result.expiresAt > this.now() + 31 * 86400000) throw new Error('Invalid gateway registration')
          const entry = { ...registration, credential: result.credential, expiresAt: result.expiresAt }
          const old = state.registrations.filter(r => same(r, registration)
            || (registration.kind !== 'liveactivity-update' && r.server === registration.server && r.kind === registration.kind))
          // A renewal reuses its gateway row, so its old credential is already invalid. A token
          // rotation creates a different row and must explicitly revoke the old destination.
          const id = entry.credential.split('.')[0]
          this.retire(state, old.filter(r => r.credential.split('.')[0] !== id))
          state.registrations = state.registrations.filter(r => !old.includes(r))
          state.registrations.push(entry)
          await this.deps.save(state)
          await this.flush(state)
          return entry
        } catch (error) {
          const code = String(object(error).code ?? '')
          if (attempt === 0 && ((error instanceof GatewayHTTPError && error.status === 401) || code.includes('APP_ATTEST_INVALID_KEY'))) {
            state.keyId = null; state.verified = false; await this.deps.save(state); continue
          }
          throw error
        }
      }
      throw new Error('App verification unavailable')
    })
  }
  revokeServer(server: string): Promise<void> {
    return this.run(async () => {
      const state = await this.load(), origin = new URL(server).origin
      this.retire(state, state.registrations.filter(r => r.server === origin))
      await this.deps.save(state); await this.flush(state)
    })
  }
  revoke(input: GatewayInput): Promise<void> {
    return this.run(async () => {
      const state = await this.load()
      this.retire(state, state.registrations.filter(r => same(r, { ...input, server: new URL(input.server).origin, token: input.token.toLowerCase() })))
      await this.deps.save(state); await this.flush(state)
    })
  }
  flushRevocations(): Promise<void> { return this.run(async () => { await this.flush(await this.load()) }) }
}
