import type { AndroidGatewayEnrollmentClient } from './androidGatewayEnrollment'
import { registerPush, type PushStatus } from './pushGatewayRegistration.ts'

type Body = { token: string; deviceName: string; gateway?: { credential: string } | null }
type Dependencies<T extends PushStatus> = {
  register(body: Body): Promise<T>
  client: Pick<AndroidGatewayEnrollmentClient, 'get' | 'revoke' | 'revokeServer'>
  current(): boolean
}

/** Android's server handoff, shared by the native adapter and lifecycle tests. */
export function registerAndroidPush<T extends PushStatus>(c: { baseURL: string; key: string }, body: Body, deps: Dependencies<T>): Promise<T> {
  return registerPush<T, 'android-alert'>(c, body, 'android-alert', {
    register: async payload => {
      const result = await deps.register(payload as Body)
      // An incomplete gateway response must never stop local medicine/daily reminders.
      if (result.delivery === 'gateway' && (!Number.isSafeInteger(result.gatewayExpiresAt) || (result.gatewayExpiresAt ?? 0) <= Date.now())) return { ...result, push: false }
      // Direct FCM supersedes every cached token for this origin, including a rotated token.
      if (result.push && result.delivery === 'direct') await deps.client.revokeServer(c.baseURL).catch(() => {})
      return result
    },
    canEnroll: status => status.gatewayAvailable === true,
    enroll: input => deps.client.get(input), revoke: input => deps.client.revoke(input), current: deps.current,
  })
}
