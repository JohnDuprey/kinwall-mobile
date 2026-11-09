import type { GatewayKind } from './gatewayEnrollment'

type Connection = { baseURL: string; key: string }
/** Why push stayed off, for the web settings: the server has no public address, the app or phone
 * couldn't be verified (or the gateway was out of reach), or the server didn't take the credential. */
export type PushProblem = 'address' | 'device' | 'server'
export type PushStatus = { push: boolean; delivery?: 'direct' | 'gateway' | 'unavailable'; gatewayExpiresAt?: number; gatewayAvailable?: boolean; gatewayServer?: string | null; problem?: PushProblem }
type Body = { token: string; [key: string]: unknown; gateway?: { credential: string } | null }
type Dependencies<T extends PushStatus, K extends string> = {
  register(body: Body): Promise<T>
  enroll(input: { server: string; token: string; kind: K; app?: string }): Promise<{ credential: string; expiresAt: number }>
  revoke(input: { server: string; token: string; kind: K }): Promise<void>
  current?(): boolean
  canEnroll?(status: T): boolean
}

/** Hosted and custom direct APNs servers finish after the first request, without touching the
 * gateway. Older servers with working push keep that same behavior. */
export async function registerPush<T extends PushStatus, K extends GatewayKind | 'android-alert'>(connection: Connection, body: Body, kind: K, deps: Dependencies<T, K>): Promise<T> {
  const first = await deps.register(body)
  if (first.delivery === undefined) return first
  if (first.push && (first.delivery !== 'gateway' || (first.gatewayExpiresAt ?? 0) > Date.now() + 5 * 60000)) return first
  if (deps.canEnroll && !deps.canEnroll(first)) return first.push ? first : { ...first, problem: 'address' }
  // The gateway binds a credential to the server's canonical address, and the server accepts only
  // that one; a family often reaches it another way (a LAN IP, another port). `app` remembers this
  // connection so leaving it still revokes the credential.
  const server = canonical(first.gatewayServer) ?? connection.baseURL
  const app = new URL(connection.baseURL).origin
  const input = { server, token: body.token, kind, ...(new URL(server).origin !== app ? { app: connection.baseURL } : {}) }
  let issued = false
  try {
    const credential = await deps.enroll(input)
    issued = true
    if (deps.current && !deps.current()) { await deps.revoke(input); return first }
    const registered = await deps.register({ ...body, gateway: { credential: credential.credential } })
    if (deps.current && !deps.current()) { await deps.revoke(input); return { ...registered, push: false } }
    if (!registered.push) { await deps.revoke(input); return { ...registered, problem: 'server' } }
    return registered
  } catch {
    // Failed enrollment cannot turn off local reminders. Revoke any newly issued capability
    // if the server handoff failed, including an ambiguous timeout after it accepted the body.
    if (issued) {
      await deps.revoke(input).catch(() => {})
      return { ...first, push: false, problem: 'server' }
    }
    const kept = first.push && first.delivery === 'gateway' && (first.gatewayExpiresAt ?? 0) <= Date.now() ? { ...first, push: false } : first
    return kept.push ? kept : { ...kept, problem: 'device' }
  }
}

/** The server's canonical origin, when it sent a usable one (older servers send none). */
function canonical(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined
  try {
    const url = new URL(value)
    return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password ? url.origin : undefined
  } catch { return undefined }
}
