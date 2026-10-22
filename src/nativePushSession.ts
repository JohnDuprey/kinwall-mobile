type Connection = { baseURL: string; key: string }
export type PushRegistration = { baseURL: string; id: string; push: boolean; expiresAt?: number }
export const pushRegistrationActive = (r: PushRegistration | null, server: string, now = Date.now()) =>
  r?.baseURL === server && r.push && (r.expiresAt === undefined || r.expiresAt > now)
type Dependencies = {
  register(c: Connection, token: string): Promise<{ push: boolean; subscription: { id: string }; gatewayExpiresAt?: number }>
  remove(c: Connection, id: string): Promise<void>
  changed(r: PushRegistration | null): void
}

/** Serialize registration and cleanup so a response arriving after sign-out cannot register the
 * old family again. Token refreshes use the same server subscription and preserve preferences. */
export class NativePushSession {
  private device: Connection | null = null
  private epoch = 0
  private queue: Promise<unknown> = Promise.resolve()
  registration: PushRegistration | null = null
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
      const result = await this.deps.register(c, token)
      if (epoch !== this.epoch) { await this.deps.remove(c, result.subscription.id); return }
      this.registration = { baseURL: c.baseURL, id: result.subscription.id, push: result.push,
        ...(result.gatewayExpiresAt !== undefined ? { expiresAt: result.gatewayExpiresAt } : {}) }
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
