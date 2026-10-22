import * as Notifications from 'expo-notifications'
import * as SecureStore from 'expo-secure-store'
import { Platform } from 'react-native'
import KinwallNative from '../modules/kinwall-native'
import { api, ApiError, type Connection } from './api'
import { NativePushSession, type PushRegistration } from './nativePushSession'

const SAVED = 'nativePushRegistration', DISABLED = 'nativePushDisabledFor'
// Background reminder refreshes run while locked. Keep this registration metadata readable then
// so they do not mistakenly recreate local medicine reminders alongside working APNs delivery.
const STORAGE = { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY }
let wanted: Connection | null = null
let canRegister = false
const listeners = new Set<() => void>()
export const nativePushAvailable = () => Platform.OS === 'ios' && KinwallNative?.pushEnabled?.() === true
export function savedNativePush(): PushRegistration | null {
  try {
    const r = JSON.parse(SecureStore.getItem(SAVED) ?? 'null')
    return r && typeof r.baseURL === 'string' && typeof r.id === 'string' && typeof r.push === 'boolean' ? r : null
  } catch { return null }
}
export const remoteMedicineReminders = (baseURL: string) => {
  const r = savedNativePush()
  return nativePushAvailable() && r?.baseURL === baseURL && r.push
}
export const onNativePushChange = (f: () => void) => { listeners.add(f); return () => { listeners.delete(f) } }
async function request<T>(c: Connection, method: string, path: string, body?: unknown): Promise<T> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 10_000)
  try { return await api<T>(c.baseURL, c.key, method, path, body, controller.signal) }
  finally { clearTimeout(timer) }
}
const session = new NativePushSession({
  register: (c, token) => request(c, 'PUT', 'api/push/native', { token, deviceName: Platform.OS === 'ios' && Platform.isPad ? 'Kinwall iPad' : 'Kinwall iPhone' }),
  remove: async (c, id) => {
    try { await request(c, 'DELETE', `api/push/subscriptions/${encodeURIComponent(id)}`) }
    catch (e) { if (!(e instanceof ApiError && e.status === 404)) throw e }
  },
  changed: r => {
    try { if (r) SecureStore.setItem(SAVED, JSON.stringify(r), STORAGE); else SecureStore.setItem(SAVED, 'null', STORAGE) } catch {}
    for (const f of listeners) f()
  },
})

/** Called after the permission prompt and on resume, using the page's current sign-in. No Expo
 * push service is involved: the native APNs token goes only to this family's server. */
export async function syncNativePush(c?: Connection): Promise<void> {
  if (!nativePushAvailable()) return
  if (c && (!wanted || wanted.baseURL !== c.baseURL || wanted.key !== c.key)) {
    if (wanted && wanted.baseURL !== c.baseURL) await clearNativePush()
    wanted = c; session.setDevice(c)
    const saved = savedNativePush()
    if (!session.registration && saved?.baseURL === c.baseURL) session.registration = saved
  }
  const current = wanted
  if (!current) return
  const permission = await Notifications.getPermissionsAsync()
  if (!permission.granted || SecureStore.getItem(DISABLED) === current.baseURL) {
    canRegister = false
    await session.clear(); session.setDevice(current)
    return
  }
  canRegister = true
  let timeout: ReturnType<typeof setTimeout> | undefined
  const token = await Promise.race([Notifications.getDevicePushTokenAsync(), new Promise<never>((_, reject) => { timeout = setTimeout(() => reject(new Error('Push token request timed out')), 10_000) })]).finally(() => clearTimeout(timeout))
  if (wanted !== current || token.type !== 'ios' || typeof token.data !== 'string') return
  await session.register(token.data)
}
// Do not call getDevicePushTokenAsync from its listener (it can trigger the listener again).
Notifications.addPushTokenListener(token => {
  if (canRegister && wanted && token.type === 'ios' && typeof token.data === 'string' && SecureStore.getItem(DISABLED) !== wanted.baseURL) session.register(token.data).catch(() => {})
})
export async function setNativePushEnabled(on: boolean): Promise<void> {
  if (!wanted) return
  if (on) await SecureStore.deleteItemAsync(DISABLED)
  else SecureStore.setItem(DISABLED, wanted.baseURL, STORAGE)
  await syncNativePush()
}
export async function clearNativePush(): Promise<void> {
  canRegister = false
  wanted = null
  await session.clear().catch(() => {})
  await Notifications.dismissAllNotificationsAsync().catch(() => {})
  await SecureStore.deleteItemAsync(SAVED)
  await SecureStore.deleteItemAsync(DISABLED)
}
