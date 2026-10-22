import type { GatewayInput, GatewayKind } from './gatewayEnrollment'

type Connection = { baseURL: string; key: string }
export type PushStatus = { push: boolean; delivery?: 'direct' | 'gateway' | 'unavailable'; gatewayExpiresAt?: number }
type Body = { token: string; [key: string]: unknown; gateway?: { credential: string } | null }
type Dependencies<T extends PushStatus> = {
  register(body: Body): Promise<T>
  enroll(input: GatewayInput): Promise<{ credential: string; expiresAt: number }>
  revoke(input: GatewayInput): Promise<void>
  current?(): boolean
}

/** Hosted and custom direct APNs servers finish after the first request, without touching the
 * gateway. Older servers with working push keep that same behavior. */
export async function registerPush<T extends PushStatus>(connection: Connection, body: Body, kind: GatewayKind, deps: Dependencies<T>): Promise<T> {
  const first = await deps.register(body)
  if (first.delivery === undefined) return first
  if (first.push && (first.delivery !== 'gateway' || (first.gatewayExpiresAt ?? 0) > Date.now() + 5 * 60000)) return first
  const input = { server: connection.baseURL, token: body.token, kind }
  let issued = false
  try {
    const credential = await deps.enroll(input)
    issued = true
    if (deps.current && !deps.current()) { await deps.revoke(input); return first }
    const registered = await deps.register({ ...body, gateway: { credential: credential.credential } })
    if (deps.current && !deps.current()) { await deps.revoke(input); return { ...registered, push: false } }
    if (!registered.push) await deps.revoke(input)
    return registered
  } catch {
    // Failed enrollment cannot turn off local reminders. Revoke any newly issued capability
    // if the server handoff failed, including an ambiguous timeout after it accepted the body.
    if (issued) {
      await deps.revoke(input).catch(() => {})
      return { ...first, push: false }
    }
    return first.push && first.delivery === 'gateway' && (first.gatewayExpiresAt ?? 0) <= Date.now() ? { ...first, push: false } : first
  }
}
