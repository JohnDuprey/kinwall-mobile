export type RoutineDecision = { enabled: boolean; appMode: 'selected' | 'all'; locked: boolean; validUntil: string; checkedAt: string; allowedWebsitesOnly?: boolean; allowedWebDomains?: string[] }
export function routineDecision(value: unknown, now = Date.now()): RoutineDecision | null {
  if (!value || typeof value !== 'object') return null
  const s = value as Record<string, unknown>
  if (typeof s.enabled !== 'boolean' || typeof s.locked !== 'boolean' || typeof s.validUntil !== 'string' || typeof s.checkedAt !== 'string') return null
  const until = Date.parse(s.validUntil), checked = Date.parse(s.checkedAt)
  if (!Number.isFinite(until) || !Number.isFinite(checked) || checked > now + 60000 || now - checked > 60000 || until - checked > 26 * 3600000) return null
  const appMode = s.appMode ?? 'selected'
  if (appMode !== 'selected' && appMode !== 'all') return null
  const allowedWebsitesOnly = s.allowedWebsitesOnly ?? false, domains = s.allowedWebDomains ?? []
  if (typeof allowedWebsitesOnly !== 'boolean' || !Array.isArray(domains) || domains.length > 40 || !domains.every(d => typeof d === 'string' && d.length <= 253 && /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]+$/.test(d)) || (allowedWebsitesOnly && !domains.length)) return null
  return { appMode, allowedWebsitesOnly, allowedWebDomains: domains as string[], enabled: s.enabled, locked: s.enabled && (s.locked || until <= now), validUntil: s.validUntil, checkedAt: s.checkedAt }
}
export function routineRequest(value: unknown): { action: 'setup' | 'sync' | 'chooseApps' | 'authorize'; memberId: string } | null {
  if (!value || typeof value !== 'object') return null
  const m = value as Record<string, unknown>
  if ((m.action !== 'setup' && m.action !== 'sync' && m.action !== 'chooseApps' && m.action !== 'authorize') || typeof m.memberId !== 'string' || !/^[a-zA-Z0-9_-]{1,100}$/.test(m.memberId)) return null
  return { action: m.action, memberId: m.memberId }
}
