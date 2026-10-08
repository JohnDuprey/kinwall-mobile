// The slice of Kinwall's REST API the shell and the Android widget need (KinwallKit stays the
// Swift side's client). One fetch per call; callers own caching.

import type { ChoreDay, MedicationDay } from './reminderPlans'
import type { FamilyList, ListDetail } from './widgetData'

export type Connection = { baseURL: string; key: string }

export class ApiError extends Error {
  status: number
  constructor(status: number, message: string) { super(message); this.status = status } // no parameter property: node runs this file in its tests
}

export type EventInstance = {
  id: string; title: string
  /** ISO instant for timed events; YYYY-MM-DD for all-day ones. */
  start: string; allDay: boolean; location?: string | null; memberIds?: string[]
  /** Minutes before start (or before leaveAt when remindBeforeLeave) to remind. */
  reminders?: number[] | null; leaveAt?: string | null; remindBeforeLeave?: boolean
}
export type BoardEvent = { id: string; title: string; start: string; end: string; allDay: boolean; color?: string | null; leaveAt?: string | null; date: string }
export type Board = {
  today: string
  events: BoardEvent[]
  chores: { memberId: string | null; name: string | null; avatar: string | null; remaining: number; total: number }[]
}

export async function api<T>(baseURL: string, key: string | null, method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (key) headers.Authorization = `Bearer ${key}`
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  const res = await fetch(new URL(path, baseURL).toString(), { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
  if (!res.ok) {
    const e = (await res.json().catch(() => null)) as { error?: string } | null
    throw new ApiError(res.status, e?.error ?? `${res.status} ${res.statusText}`)
  }
  const text = await res.text() // a write may answer with no body
  return (text ? JSON.parse(text) : null) as T
}

/** Does this address answer like a Kinwall server? */
export async function isKinwall(baseURL: string): Promise<boolean> {
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), 10_000)
  try {
    const res = await fetch(new URL('api/health', baseURL).toString(), { headers: { Accept: 'application/json' }, signal: ctl.signal })
    return res.status === 200
  } finally { clearTimeout(t) }
}

export const events = (c: Connection, from: Date, to: Date) =>
  api<EventInstance[]>(c.baseURL, c.key, 'GET', `api/events?from=${encodeURIComponent(from.toISOString())}&to=${encodeURIComponent(to.toISOString())}`)
/** This key's owner: a member id on a person's own device, else "shared" or null. */
/** `householdId`: the same for every key to one family (servers from 2026-09-30 on). */
export const me = (c: Connection) => api<{ scope: string; owner: string | null; householdId?: string }>(c.baseURL, c.key, 'GET', 'api/me')

/** Does the saved widgets key still open the family the app is signed in to? Not when it's for
 * another server, has been revoked (401), or opens another household there (a key left over from
 * one family let Siri add to the wrong one). Can't tell (offline, an older server): keep it. */
export async function widgetKeyFits(saved: Connection | null, signedIn: Connection): Promise<boolean> {
  if (!saved || saved.baseURL !== signedIn.baseURL) return false
  const [widgets, app] = await Promise.all([me(saved), me(signedIn)].map((p) => p.catch((e: unknown) => e)))
  if (widgets instanceof ApiError && widgets.status === 401) return false
  if (widgets instanceof Error || app instanceof Error) return true
  const a = (widgets as Awaited<ReturnType<typeof me>>).householdId, b = (app as Awaited<ReturnType<typeof me>>).householdId
  return !a || !b || a === b
}
export const medicationDay = (c: Connection, memberId: string) =>
  api<MedicationDay>(c.baseURL, c.key, 'GET', `api/members/${encodeURIComponent(memberId)}/medications?days=1`)
export const choresOn = (c: Connection, date: string) => api<ChoreDay[]>(c.baseURL, c.key, 'GET', `api/chores/day?date=${date}`)
export const board = (c: Connection, days = 1) => api<Board>(c.baseURL, c.key, 'GET', `api/board?days=${days}`)
/** The family's feature switches (GET /api/settings `features`, Settings → Features in Kinwall):
 * one that's missing (older servers, or offline: {}) counts as on, so test with `=== false`. */
export type Features = Partial<Record<string, boolean>>
/** The slice of GET /api/settings the widgets read; {} offline. */
export type Settings = { features?: Features; medications?: boolean }
export const settings = (c: Connection) => api<Settings>(c.baseURL, c.key, 'GET', 'api/settings').then((s) => s ?? {}, (): Settings => ({}))
export const features = (c: Connection) => settings(c).then((s) => s.features ?? {})
export const members = (c: Connection) => api<{ id: string; name: string; avatar?: string | null }[]>(c.baseURL, c.key, 'GET', 'api/members')
/** memberId: who gets the points for an Anyone chore; the key's own person otherwise. Left out
 * when null: the server's memberId is optional, not nullable, and answers null with a 400. */
export const completeChore = (c: Connection, id: string, date: string, memberId: string | null) =>
  api<unknown>(c.baseURL, c.key, 'POST', `api/chores/${encodeURIComponent(id)}/complete`, memberId ? { date, memberId } : { date })
export const lists = (c: Connection) => api<FamilyList[]>(c.baseURL, c.key, 'GET', 'api/lists')
export const list = (c: Connection, id: string) => api<ListDetail>(c.baseURL, c.key, 'GET', `api/lists/${encodeURIComponent(id)}`)
export const setItemDone = (c: Connection, listId: string, itemId: string, done: boolean) =>
  api<unknown>(c.baseURL, c.key, 'PATCH', `api/lists/${encodeURIComponent(listId)}/items/${encodeURIComponent(itemId)}`, { done })
/** The doses due now (names only where the server shares them; the widget shows only the count). */
export const dueDoses = (c: Connection) => api<{ doses: unknown[] }>(c.baseURL, c.key, 'GET', 'api/medications/due')
/** An everyday-access key for widgets or the watch; the plaintext comes back once. */
export const createDeviceKey = (baseURL: string, key: string, name: string) =>
  api<{ id: string; key: string }>(baseURL, key, 'POST', 'api/device-keys', { name })
export const revokeOwnKey = (c: Connection) => api<{ ok: boolean }>(c.baseURL, c.key, 'DELETE', 'api/device-keys/self')

/** Timed events today that haven't ended: the one under way, and the next one. */
export function nowAndNext(b: Board, now = new Date()): { now?: BoardEvent; next?: BoardEvent } {
  const today = b.events.filter((e) => e.date === b.today && !e.allDay)
  const t = now.getTime()
  const current = today.find((e) => Date.parse(e.start) <= t && t < Date.parse(e.end))
  const next = today.filter((e) => Date.parse(e.start) > t).sort((a, b) => Date.parse(a.start) - Date.parse(b.start))[0]
  return { now: current, next }
}
