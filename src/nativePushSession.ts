type Connection = { baseURL: string; key: string }
import type { PushProblem } from './pushGatewayRegistration'

export type PushRegistration = { baseURL: string; id: string; push: boolean; expiresAt?: number; problem?: PushProblem }
export const pushRegistrationActive = (r: PushRegistration | null, server: string, now = Date.now()) =>
  r?.baseURL === server && r.push && (r.expiresAt === undefined || r.expiresAt > now)
type Dependencies = {
  register(c: Connection, token: string): Promise<{ push: boolean; subscription: { id: string }; gatewayExpiresAt?: number; problem?: PushProblem }>
  remove(c: Connection, id: string): Promise<void>
  changed(r: PushRegistration | null): void
  now?(): number
}
// The app asks to register on every resume and page load. The same token for the same sign-in is
// sent again only this often, or when a gateway credential is within RENEW_MS of expiring.
const REREGISTER_MS = 12 * 3600_000
const RENEW_MS = 86400_000

/** Serialize registration and cleanup so a response arriving after sign-out cannot register the
 * old family again. Token refreshes use the same server subscription and preserve preferences. */
export class NativePushSession {
  private device: Connection | null = null
  private epoch = 0
  private queue: Promise<unknown> = Promise.resolve()
  registration: PushRegistration | null = null
  private sent: { device: Connection; token: string; at: number } | null = null // in memory: a cold start sends once
  private deps: Dependencies
  constructor(deps: Dependencies) { this.deps = deps }
  setDevice(c: Connection) { this.epoch++; this.device = c }
  private run(task: () => Promise<void>) {
    const next = this.queue.catch(() => {}).then(task)
    this.queue = next
    return next
  }
  register(token: string) {
    const c = this.device, epoch = this.epoch
    return this.run(async () => {
      if (!c || epoch !== this.epoch) return
      const now = this.deps.now?.() ?? Date.now(), r = this.registration, last = this.sent
      if (r && last && last.device === c && last.token === token && now - last.at < REREGISTER_MS
        && (r.expiresAt === undefined || r.expiresAt - now > RENEW_MS)) return
      const result = await this.deps.register(c, token)
      if (epoch !== this.epoch) { await this.deps.remove(c, result.subscription.id); return }
      this.registration = { baseURL: c.baseURL, id: result.subscription.id, push: result.push,
        ...(result.gatewayExpiresAt !== undefined ? { expiresAt: result.gatewayExpiresAt } : {}),
        ...(!result.push && result.problem ? { problem: result.problem } : {}) }
      this.sent = { device: c, token, at: now }
      this.deps.changed(this.registration)
    })
  }
  clear() {
    const c = this.device
    this.epoch++; this.device = null
    return this.run(async () => {
      const r = this.registration
      this.registration = null
      this.deps.changed(null)
      if (c && r && c.baseURL === r.baseURL) await this.deps.remove(c, r.id)
    })
  }
}
