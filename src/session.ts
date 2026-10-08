import * as SecureStore from 'expo-secure-store'
import { type Tokens, clearTokens, loadTokens, refresh, revoke, saveTokens } from './oauth'
import { needsRefresh, refreshed } from './tokenRefresh'
import { clearReminders } from './reminders'
import { clearSpotlight } from './spotlight'
import { revokeWidgetKey, shareKey, watchSignOut } from './sharedKey'
import { clearAppearance } from './theme'
import { reloadWidgets } from './widgets'

// How this device is signed in to the household: OAuth tokens (kept fresh here), or a paired
// key the web app holds itself. Null means "show the sign-in screen".
export type Session = { mode: 'oauth'; tokens: Tokens } | { mode: 'paired' } | { mode: 'demo' } | null

const PAIRED = 'signedInWithPairing'

export async function loadSession(server: string): Promise<Session> {
  const tokens = await loadTokens()
  if (tokens?.baseURL === server) return { mode: 'oauth', tokens }
  if ((await SecureStore.getItemAsync(PAIRED)) === '1') return { mode: 'paired' }
  return null
}

export async function signedIn(tokens: Tokens): Promise<Session> {
  await saveTokens(tokens)
  await SecureStore.deleteItemAsync(PAIRED)
  return { mode: 'oauth', tokens }
}

export async function choosePairing(): Promise<Session> {
  await SecureStore.setItemAsync(PAIRED, '1')
  return { mode: 'paired' }
}

export { needsRefresh }

let refreshing: Promise<Tokens | null> | null = null
/** Tokens good for at least five minutes, refreshing if needed (`force`: now, e.g. the server
 * rejected keys that look fine). Null when the grant is gone (revoked, or the refresh token
 * expired): the caller signs out. One refresh at a time here (refresh tokens rotate); the share
 * sheet and Siri refresh apart from it (src/tokenRefresh.ts). */
export function freshTokens(t: Tokens, force = false): Promise<Tokens | null> {
  if (!force && !needsRefresh(t)) return Promise.resolve(t)
  refreshing ??= refreshed(t, force, { load: loadTokens, refresh, save: saveTokens }).finally(() => { refreshing = null })
  return refreshing
}

/** Back to the sign-in screen, ending the OAuth grant on the server. */
export async function signOut(session: Session): Promise<void> {
  if (session?.mode === 'oauth') await revoke(session.tokens)
  await clearTokens()
  await shareKey(null)
  await revokeWidgetKey()
  await clearReminders()
  await clearSpotlight()
  await watchSignOut()
  await SecureStore.deleteItemAsync(PAIRED)
  await clearAppearance() // the next family starts from the app's own colors
  reloadWidgets()
}
