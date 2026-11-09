import type { PushRegistration } from './nativePushSession'

/** Initialize on every document load as well as registration changes. Metadata only: the web
 * settings PATCH the existing subscription, preserving identity and unrelated preferences. */
export function nativePushPageScript(server: string, registration: PushRegistration | null, enabled: boolean, now = Date.now()): string {
  const mine = enabled && registration?.baseURL === server ? registration : null
  const ready = !!mine?.push && (mine.expiresAt === undefined || mine.expiresAt > now)
  // Why it isn't ready, so the settings can say what to fix (pushGatewayRegistration.ts PushProblem).
  const problem = !ready && mine?.problem && ['address', 'device', 'server'].includes(mine.problem) ? mine.problem : null
  return `if (location.origin === ${JSON.stringify(new URL(server).origin)} && window.kinwallNative) { window.kinwallNative.pushReady = ${JSON.stringify(ready)}; window.kinwallNative.pushProblem = ${JSON.stringify(problem)}; try { ${mine ? `localStorage.setItem('kinwall.pushSubId', ${JSON.stringify(mine.id)});` : `localStorage.removeItem('kinwall.pushSubId');`} } catch (e) {} window.dispatchEvent(new Event('kinwallnative')); } true;`
}
