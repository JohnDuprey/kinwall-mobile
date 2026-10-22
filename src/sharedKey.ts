import * as SecureStore from 'expo-secure-store'
import { Platform } from 'react-native'
import KinwallNative from '../modules/kinwall-native'
import { personalWatchConnection } from './watchConnection'
import { type Connection, createDeviceKey, revokeOwnKey, widgetKeyFits, watchKeyFits } from './api'

// The widgets' and the Watch's own everyday-access keys (docs/WIDGETS-AND-WATCH.md): minted once
// per server with whatever key the app is signed in with, revoked on sign-out. Never the app's
// rotating sign-in itself.
//
// iOS: kept by the native module exactly where KinwallKit's KeychainConnectionStore looks
// (service, account "household", the shared group for the widgets' key), so the widgets, Watch
// and Siri read it. Android: SecureStore; the widget there renders in JavaScript.
type Store = { service: string; shared: boolean }
const WIDGETS: Store = { service: 'family.kinwall.widgets', shared: true }
const WATCH: Store = { service: 'family.kinwall.watch', shared: false }
const secure = (s: Store) => ({ keychainService: s.service, keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK })

async function load(s: Store): Promise<Connection | null> {
  const v = await (KinwallNative ? KinwallNative.keychainGet(s.service, s.shared) : SecureStore.getItemAsync('household', secure(s))).catch(() => null)
  return v ? (JSON.parse(v) as Connection) : null
}
const save = (s: Store, c: Connection | null) =>
  KinwallNative ? KinwallNative.keychainSet(s.service, s.shared, c && JSON.stringify(c))
    : c ? SecureStore.setItemAsync('household', JSON.stringify(c), secure(s)) : SecureStore.deleteItemAsync('household', secure(s))

export const widgetConnection = () => load(WIDGETS)
export const pairedConnection = () => load({ service: 'family.kinwall.share', shared: true })

/** iOS: a paired device's own sign-in, for the share extension to import a recipe with (an OAuth
 * sign-in shares its tokens instead, src/oauth.ts). Null clears it. */
export const shareKey = (c: Connection | null) =>
  KinwallNative?.keychainSet('family.kinwall.share', true, c && JSON.stringify(c)).catch(() => {})

/** Once the page is signed in, make sure the widgets (and Siri) have a key for this family:
 * a new one when the saved one is for another server or household, or was revoked. */
export async function ensureWidgetKey(baseURL: string, key: string): Promise<void> {
  const saved = await load(WIDGETS)
  if (await widgetKeyFits(saved, { baseURL, key })) return
  const device = Platform.OS === 'ios' ? (Platform.isPad ? 'iPad' : 'iPhone') : 'Android'
  const minted = await createDeviceKey(baseURL, key, `Widgets on ${device}`).catch(() => null)
  if (!minted) return
  if (saved) await revokeOwnKey(saved).catch(() => {}) // the other family's key, while it still works
  await save(WIDGETS, { baseURL, key: minted.key })
}

export async function revokeWidgetKey(): Promise<void> {
  const saved = await load(WIDGETS)
  if (saved) await revokeOwnKey(saved).catch(() => {})
  await save(WIDGETS, null).catch(() => {})
}

// Only the active app supplies this credential; never persist another copy of its sign-in.
let watchSource: Connection | null = null
let watchSync: Promise<void> | null = null

/** iOS: mint the Watch's personal key with the phone sign-in, never its shared widgets key. */
export function syncWatch(signedIn?: Connection): Promise<void> {
  if (signedIn) watchSource = signedIn
  if (watchSync) return signedIn ? watchSync.then(() => watchSource === signedIn ? syncWatch() : undefined) : watchSync
  watchSync = syncPersonalWatch().finally(() => { watchSync = null })
  return watchSync
}

async function syncPersonalWatch(): Promise<void> {
  if (!KinwallNative?.watchAppInstalled()) return
  const source = watchSource
  if (!source) return // wait for the signed-in web page to provide its current credential
  const saved = await load(WATCH)
  const watch = await personalWatchConnection(source, saved, () => watchSource === source, { createDeviceKey, revokeOwnKey, watchKeyFits })
  if (!watch) return
  if (watchSource !== source) { if (watch !== saved) await revokeOwnKey(watch).catch(() => {}); return }
  if (watch !== saved) await save(WATCH, watch)
  if (watchSource !== source) return
  try { KinwallNative.updateWatch({ server: watch.baseURL, key: watch.key }) } catch {}
}

export async function watchSignOut(): Promise<void> {
  watchSource = null
  await watchSync?.catch(() => {})
  const watch = await load(WATCH)
  if (watch) await revokeOwnKey(watch).catch(() => {})
  await save(WATCH, null).catch(() => {})
  try { KinwallNative?.updateWatch({ signedOut: true }) } catch {}
}
