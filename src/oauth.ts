import * as Crypto from 'expo-crypto'
import * as SecureStore from 'expo-secure-store'
import * as WebBrowser from 'expo-web-browser'
import { Platform } from 'react-native'
import KinwallNative from '../modules/kinwall-native'

// Signing in with Kinwall's OAuth (the same authorization server MCP clients use): the app
// registers itself, opens the consent screen in the system's auth sheet (where passkeys work on
// any domain), and swaps the returned code for tokens. Access tokens last an hour; refresh
// tokens 90 days and rotate on every use. The app's link scheme is reverse-domain (RFC 8252).
export const REDIRECT_URI = 'family.kinwall.app:/oauth'

export type Tokens = { baseURL: string; clientId: string; accessToken: string; refreshToken: string; expiresAt: number; scope: string }

export class OAuthError extends Error {
  constructor(public code: string, message: string) { super(message) }
  /** The refresh token is gone (revoked, expired or already used): sign in again. */
  get needsSignIn() { return this.code === 'invalid_grant' }
}

const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const random = (n: number) => base64url(Crypto.getRandomValues(new Uint8Array(n)))
const form = (fields: Record<string, string>) => Object.entries(fields).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&')

async function tokenRequest(baseURL: string, clientId: string, fields: Record<string, string>): Promise<Tokens> {
  const res = await fetch(new URL('oauth/token', baseURL).toString(), { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form(fields) })
  const r = (await res.json().catch(() => ({}))) as { access_token: string; refresh_token: string; expires_in: number; scope: string; error?: string; error_description?: string }
  if (!res.ok) throw new OAuthError(r.error ?? `http_${res.status}`, r.error_description ?? r.error ?? `HTTP ${res.status}`)
  return { baseURL, clientId, accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: Date.now() + r.expires_in * 1000, scope: r.scope }
}

/** The whole sign-in: register, consent sheet, code for tokens. Null when the person closed the sheet. */
export async function signIn(baseURL: string): Promise<Tokens | null> {
  const reg = await fetch(new URL('oauth/register', baseURL).toString(), {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_name: `Kinwall for ${Platform.OS === 'ios' ? 'iPhone' : 'Android'}`, redirect_uris: [REDIRECT_URI] }),
  })
  if (!reg.ok) throw new OAuthError('register', 'This server does not offer app sign-in.')
  const { client_id: clientId } = (await reg.json()) as { client_id: string }
  const verifier = random(32)
  const challenge = base64url(new Uint8Array(await Crypto.digest(Crypto.CryptoDigestAlgorithm.SHA256, new TextEncoder().encode(verifier))))
  const state = random(12)
  const url = new URL('oauth/authorize', baseURL)
  url.search = form({ response_type: 'code', client_id: clientId, redirect_uri: REDIRECT_URI, code_challenge: challenge, code_challenge_method: 'S256', scope: 'kinwall:admin', state })
  const result = await WebBrowser.openAuthSessionAsync(url.toString(), REDIRECT_URI)
  if (result.type !== 'success') return null
  const q = new URL(result.url.replace(/^family\.kinwall\.app:\/*/, 'https://callback/')).searchParams
  const error = q.get('error')
  if (error) throw new OAuthError(error, error === 'access_denied' ? 'Sign-in was declined.' : q.get('error_description') ?? error)
  const code = q.get('code')
  if (q.get('state') !== state || !code) throw new OAuthError('invalid_response', "The sign-in didn't come back as expected. Try again.")
  return tokenRequest(baseURL, clientId, { grant_type: 'authorization_code', code, code_verifier: verifier, client_id: clientId, redirect_uri: REDIRECT_URI })
}

export const refresh = (t: Tokens) => tokenRequest(t.baseURL, t.clientId, { grant_type: 'refresh_token', refresh_token: t.refreshToken, client_id: t.clientId })

/** Ends the grant on the server. Best effort: 10 s, then give up. */
export async function revoke(t: Tokens) {
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), 10_000)
  await fetch(new URL('oauth/revoke', t.baseURL).toString(), { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form({ token: t.refreshToken, client_id: t.clientId }), signal: ctl.signal }).catch(() => {})
  clearTimeout(timer)
}

// The tokens, in the keychain / keystore. iOS keeps them in the shared Keychain group, where the
// share extension (targets/share) reads them to import a recipe, refreshing and saving them back.
// Earlier builds kept them in SecureStore; the first load moves them.
const STORE = { keychainService: 'family.kinwall.oauth', keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK }
const SHARED = 'family.kinwall.oauth'
export async function loadTokens(): Promise<Tokens | null> {
  let s = KinwallNative ? await KinwallNative.keychainGet(SHARED, true).catch(() => null) : null
  if (!s && (s = await SecureStore.getItemAsync('household', STORE)) && KinwallNative) {
    await KinwallNative.keychainSet(SHARED, true, s)
    await SecureStore.deleteItemAsync('household', STORE)
  }
  return s ? (JSON.parse(s) as Tokens) : null
}
export const saveTokens = (t: Tokens) =>
  KinwallNative ? KinwallNative.keychainSet(SHARED, true, JSON.stringify(t)) : SecureStore.setItemAsync('household', JSON.stringify(t), STORE)
export async function clearTokens() {
  await KinwallNative?.keychainSet(SHARED, true, null)
  await SecureStore.deleteItemAsync('household', STORE)
}
