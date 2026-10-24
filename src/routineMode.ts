type RoutineHours = { start: string; cutoff: string }
export type RoutineCalendar = RoutineHours & { timezone: string; days: (RoutineHours | null)[]; scheduleOnly: boolean }
export type RoutineDecision = { enabled: boolean; appMode: 'selected' | 'all'; locked: boolean; validUntil: string; checkedAt: string; allowedWebsitesOnly?: boolean; allowedWebDomains?: string[]; date?: string; calendar?: RoutineCalendar }
const time = (value: unknown): value is string => typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value)
function calendarPolicy(s: Record<string, unknown>): { calendar: RoutineCalendar; date: string } | null {
  if (typeof s.timezone !== 'string' || s.timezone.length > 100 || typeof s.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s.date)
    || !time(s.start) || !time(s.cutoff) || s.start >= s.cutoff) return null
  const date = Date.parse(s.date + 'T12:00:00Z')
  if (!Number.isFinite(date) || new Date(date).toISOString().slice(0, 10) !== s.date) return null
  try { new Intl.DateTimeFormat('en', { timeZone: s.timezone }).format(0) } catch { return null }
  const days = s.daySchedules ?? Array(7).fill(null)
  if (!Array.isArray(days) || days.length !== 7 || !days.every(day => day === null || (typeof day === 'object' && time(day.start) && time(day.cutoff) && day.start < day.cutoff))) return null
  const ids = s.requiredChoreIds ?? null
  if (ids !== null && (!Array.isArray(ids) || ids.length > 200 || !ids.every(id => typeof id === 'string' && id.length > 0 && id.length <= 100))) return null
  const names = s.requiredOneTimeChoreNames ?? []
  if (!Array.isArray(names) || names.length > 200 || !names.every(name => typeof name === 'string' && name.trim().length > 0)) return null
  return { date: s.date, calendar: { timezone: s.timezone, start: s.start, cutoff: s.cutoff, days: days.map(day => day === null ? null : { start: day.start, cutoff: day.cutoff }), scheduleOnly: Array.isArray(ids) && ids.length === 0 && names.length === 0 } }
}
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
  const hasCalendar = ['date', 'timezone', 'start', 'cutoff', 'daySchedules'].some(key => key in s)
  const calendar = hasCalendar ? calendarPolicy(s) : null
  if (hasCalendar && !calendar) return null
  return { ...(calendar ?? {}), appMode, allowedWebsitesOnly, allowedWebDomains: domains as string[], enabled: s.enabled, locked: s.enabled && (s.locked || until <= now), validUntil: s.validUntil, checkedAt: s.checkedAt }
}
export function routineRequest(value: unknown): { action: 'setup' | 'sync' | 'chooseApps' | 'authorize'; memberId: string } | null {
  if (!value || typeof value !== 'object') return null
  const m = value as Record<string, unknown>
  if ((m.action !== 'setup' && m.action !== 'sync' && m.action !== 'chooseApps' && m.action !== 'authorize') || typeof m.memberId !== 'string' || !/^[a-zA-Z0-9_-]{1,100}$/.test(m.memberId)) return null
  return { action: m.action, memberId: m.memberId }
}
