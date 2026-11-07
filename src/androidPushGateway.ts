import * as SecureStore from 'expo-secure-store'
import * as Crypto from 'expo-crypto'
import KinwallNative from '../modules/kinwall-native'
import { api, type Connection } from './api'
import { AndroidGatewayEnrollmentClient, type AndroidGatewayState } from './androidGatewayEnrollment'
import { GatewayHTTPError } from './gatewayEnrollment'
import { registerPush, type PushStatus } from './pushGatewayRegistration'

const SAVED = 'androidPushGatewayEnrollment'
const STORAGE = { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY }
const client = new AndroidGatewayEnrollmentClient({
  supported: () => KinwallNative?.androidGatewaySupported?.() === true,
  publicKey: () => { if (!KinwallNative?.androidGatewayPublicKey) throw new Error('Android verification unavailable'); return KinwallNative.androidGatewayPublicKey() },
  proof: data => { if (!KinwallNative?.androidGatewayProof) throw new Error('Android verification unavailable'); return KinwallNative.androidGatewayProof(data) },
  hash: async (text, encoding) => {
    const value = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, text, { encoding: encoding === 'hex' ? Crypto.CryptoEncoding.HEX : Crypto.CryptoEncoding.BASE64 })
    return encoding === 'hex' ? value : value.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  },
  load: async () => {
    const value = await SecureStore.getItemAsync(SAVED)
    try { return value ? JSON.parse(value) as AndroidGatewayState : null } catch { return null }
  },
  save: state => SecureStore.setItemAsync(SAVED, JSON.stringify(state), STORAGE),
  request: async (path, body, method = 'POST', credential) => {
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 10000)
    try {
      const response = await fetch('https://push.kinwall.family' + path, {
        method, redirect: 'error', signal: controller.signal,
        headers: { 'Content-Type': 'application/json', ...(credential ? { Authorization: `Bearer ${credential}` } : {}) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      })
      if (!response.ok) throw new GatewayHTTPError(response.status)
      const value = await response.text()
      if (value.length > 16000) throw new Error('Invalid Android gateway response')
      return JSON.parse(value)
    } finally { clearTimeout(timer) }
  },
})

export function registerAndroidGatewayPush<T extends PushStatus>(c: Connection, body: { token: string; deviceName: string }, current: () => boolean): Promise<T> {
  return registerPush<T, 'android-alert'>(c, body, 'android-alert', {
    register: async payload => {
      const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 10000)
      try {
        const result = await api<T>(c.baseURL, c.key, 'PUT', 'api/push/android', payload, controller.signal)
        // An incomplete gateway response must never stop local medicine/daily reminders.
        if (result.delivery === 'gateway' && (!Number.isSafeInteger(result.gatewayExpiresAt) || (result.gatewayExpiresAt ?? 0) <= Date.now())) return { ...result, push: false }
        if (result.push && result.delivery === 'direct') await client.revoke({ server: c.baseURL, token: body.token, kind: 'android-alert' }).catch(() => {})
        return result
      } finally { clearTimeout(timer) }
    },
    canEnroll: status => status.gatewayAvailable === true,
    enroll: input => client.get(input), revoke: input => client.revoke(input), current,
  })
}
export const revokeAndroidGatewayServer = (server: string) => client.revokeServer(server)
export const flushAndroidGatewayRevocations = () => client.flushRevocations()
