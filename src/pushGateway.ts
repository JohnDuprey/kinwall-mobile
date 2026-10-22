import * as SecureStore from 'expo-secure-store'
import KinwallNative from '../modules/kinwall-native'
import { api, type Connection } from './api'
import { GatewayEnrollmentClient, GatewayHTTPError, type GatewayKind, type GatewayState } from './gatewayEnrollment'
import { registerPush, type PushStatus } from './pushGatewayRegistration'

const STORAGE = { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY }
const SAVED = 'pushGatewayEnrollment'
const ORIGIN = 'https://push.kinwall.family'
async function gatewayRequest(path: string, body?: unknown, method: 'POST'|'DELETE' = 'POST', credential?: string): Promise<unknown> {
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 10000)
  try {
    const result = await fetch(ORIGIN + path, { method, redirect: 'error', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', ...(credential ? { Authorization: 'Bearer ' + credential } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) })
    if (!result.ok) throw new GatewayHTTPError(result.status)
    const text = await result.text()
    if (text.length > 16000) throw new Error('Invalid gateway response')
    return JSON.parse(text)
  } finally { clearTimeout(timer) }
}
const client = new GatewayEnrollmentClient({
  supported: () => KinwallNative?.appAttestSupported?.() === true,
  generateKey: () => { if (!KinwallNative?.appAttestGenerateKey) throw new Error('App verification unavailable'); return KinwallNative.appAttestGenerateKey() },
  attestKey: (key, challenge) => { if (!KinwallNative?.appAttestKey) throw new Error('App verification unavailable'); return KinwallNative.appAttestKey(key, challenge) },
  assertion: (key, data) => { if (!KinwallNative?.appAttestAssertion) throw new Error('App verification unavailable'); return KinwallNative.appAttestAssertion(key, data) },
  load: async () => { const saved = await SecureStore.getItemAsync(SAVED); try { return saved ? JSON.parse(saved) as GatewayState : null } catch { return null } },
  save: state => SecureStore.setItemAsync(SAVED, JSON.stringify(state), STORAGE),
  request: gatewayRequest,
})

export function registerGatewayPush<T extends PushStatus>(c: Connection, path: 'api/push/native'|'api/live-activities/tokens', body: { token: string; [key: string]: unknown }, kind: GatewayKind, current?: () => boolean): Promise<T> {
  return registerPush(c, body, kind, {
    register: async payload => {
      const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 10000)
      try { return await api<T>(c.baseURL, c.key, 'PUT', path, payload, controller.signal) }
      finally { clearTimeout(timer) }
    },
    enroll: input => client.get(input), revoke: input => client.revoke(input), current,
  })
}
export const revokeGatewayServer = (server: string) => client.revokeServer(server)
export const revokeGatewayToken = (server: string, token: string, kind: GatewayKind) => client.revoke({ server, token, kind })
export const flushGatewayRevocations = () => client.flushRevocations()
