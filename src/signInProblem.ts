/** A plain sentence for a failed sign-in: no "Network request failed" or "HTTP 500" for a parent. */
export function signInProblem(e: unknown, host: string): string {
  // An OAuthError (src/oauth.ts) carries a code; imported by shape so this stays testable without Expo.
  const code = e instanceof Error ? (e as { code?: unknown }).code : undefined
  if (typeof code === 'string' && e instanceof Error) {
    if (/^http_5\d\d$/.test(code) || code === 'server_error') return `${host} had a problem. Try again in a minute.`
    if (/^http_\d+$/.test(code)) return "Kinwall didn't accept the sign-in. Try again."
    return e.message
  }
  return `Couldn't reach ${host}. Check your connection and try again.`
}
