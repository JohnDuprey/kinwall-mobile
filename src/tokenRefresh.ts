import type { Tokens } from './oauth'

// The app's side of refreshing its OAuth sign-in (src/session.ts freshTokens), kept free of native
// modules so test/tokenRefresh.test.ts can run it. The share extension and the App Intents (iOS,
// KinwallKit TokenRefresh) and the share sheet (Android, ShareActivity.kt) refresh the same tokens
// in their own process. Nothing locks them out of each other: the server hands the same new pair
// to the same refresh token sent twice within 30 seconds, and every refresh starts from the saved
// tokens and, turned down, reads them again before giving up.

/** Refresh a little early so a request never goes out with a token about to lapse. */
export const needsRefresh = (t: Tokens, now = Date.now()) => t.expiresAt - now < 5 * 60_000

export type Store = { load: () => Promise<Tokens | null>; refresh: (t: Tokens) => Promise<Tokens>; save: (t: Tokens) => Promise<unknown> }

/** Tokens good for five minutes or more (`force`: refreshed now unless the saved ones are already
 * newer). Null when the grant is gone and no other process has rotated it meanwhile: sign in
 * again. Offline or a server error: the old ones, to try again later. */
export async function refreshed(t: Tokens, force: boolean, { load, refresh, save }: Store): Promise<Tokens | null> {
  const saved = async () => { const s = await load().catch(() => null); return s?.baseURL === t.baseURL ? s : null }
  const cur = (await saved()) ?? t
  if (!needsRefresh(cur) && !(force && cur.accessToken === t.accessToken)) return cur
  let next: Tokens
  try {
    next = await refresh(cur)
  } catch (e) {
    if ((e as { code?: string })?.code !== 'invalid_grant') return cur
    const again = await saved() // the share sheet or Siri may have just rotated them
    return again && again.refreshToken !== cur.refreshToken ? again : null
  }
  // Not saved, the old refresh token is spent: this pair still works for now. One more try.
  await save(next).catch(() => save(next)).catch(() => {})
  return next
}
