import * as SecureStore from 'expo-secure-store'
import { Platform } from 'react-native'
import KinwallNative, { type ActivityToken } from '../modules/kinwall-native'
import { api, type Connection } from './api'
import { type LeaveByEvent, type LeaveByPerson, leaveByAlarms } from './leaveBy'

// The Live Activities on iPhone (modules/kinwall-native/ios/LiveActivities.swift draws nothing
// itself; targets/widgets/LiveActivities.swift does): the web app says what to show
// (web/src/native.ts tellAppActivity in the kinwall repo) and WebShell hands it over here. On
// Android the same messages show ongoing notifications (modules/kinwall-native/android Countdowns.kt).

const KINDS = ['cooking', 'shopping', 'leaveBy', 'medication']
type Colors = { bg: string; fg: string; accent: string } | null

export function showActivity(kind: unknown, payload: unknown, colors: Colors) {
  if (!KinwallNative || typeof kind !== 'string' || !KINDS.includes(kind) || !payload || typeof payload !== 'object') return
  KinwallNative.activitySet(kind, JSON.stringify(payload), colors).catch(() => {}) // a payload the app can't read shows nothing
}
export function endActivity(kind: unknown) {
  if (typeof kind === 'string' && KINDS.includes(kind)) KinwallNative?.activityEnd(kind).catch(() => {})
}
/** Sign-out: nothing of this household stays on the Lock Screen (on Android, no leave-by alarm either). */
export const endAllActivities = () => { KinwallNative?.activityEnd(null).catch(() => {}); SecureStore.deleteItemAsync(OWNER).catch(() => {}) }
/** Ones whose time passed while the app was closed. */
export const endStaleActivities = () => { KinwallNative?.activityEndStale().catch(() => {}) }

/** For the page (window.kinwallNative.liveActivities): allowed in iPhone Settings, or on Android
 * notifications and the "Timers and countdowns" channel on. */
export function activitiesEnabled(): boolean | null {
  try { return KinwallNative ? KinwallNative.activitiesEnabled() : null } catch { return null }
}

// With Apple push (a paid team, docs/PLAN.md) the app gets tokens for the server, which then starts
// a leave-by activity while the app is closed and ends it on time. They're registered with the
// key the page is signed in with (the server keeps them per device), never in the demo, and the
// push-to-start token only while this device would get transition reminders (its person has them
// on and notifications are allowed): otherwise it's taken back.
let device: Connection | null = null
let wanted = false
let start: ActivityToken | null = null
const updates: ActivityToken[] = []
const put = (t: ActivityToken) => device && api(device.baseURL, device.key, 'PUT', 'api/live-activities/tokens', t).catch(() => {})
const flush = () => {
  if (!device) return
  if (start && wanted) put(start)
  while (updates.length) put(updates.shift()!)
}
export function setActivityDevice(c: Connection | null) { device = c; flush() }
export function setLeaveByPush(on: boolean) {
  if (wanted && !on && device) api(device.baseURL, device.key, 'DELETE', 'api/live-activities/tokens', {}).catch(() => {})
  wanted = on
  flush()
}
KinwallNative?.addListener('activityToken', (t) => { if (t.kind === 'start') start = t; else updates.push(t); flush() })

/** Debug builds only: a sample medicine Live Activity (family.kinwall.app:/open?debug=medication),
 * in the shape the web app sends. The demo family's Sam, never real data. */
export function showSampleMedication() {
  if (!__DEV__) return
  const now = Date.now()
  showActivity('medication', { medicationId: 'med1', date: new Date(now).toISOString().slice(0, 10), time: '12:00', memberName: 'Sam', label: "Sam's medicine", headline: "Time for Sam's medicine", dueAt: new Date(now - 5 * 60_000).toISOString(), windowEndsAt: new Date(now + 2 * 3600_000).toISOString(), stage: 'due' }, null)
}

/** Debug builds only: a sample cooking timer (family.kinwall.app:/open?debug=cooking), a long
 * recipe name and a 90-second timer that rings, in the shape the web app sends. */
export function showSampleCooking() {
  if (!__DEV__) return
  // A range (web/src/liveActivity.ts): a soft check at 1 minute, the end at 1.5.
  const check = Date.now() + 60_000, at = check + 30_000, recipe = 'Thai Coconut Curry with Crispy Tofu', body = `${recipe} · Step 3 · Finish Filling`
  showActivity('cooking', {
    recipe, timer: 'Rice', step: 'Step 3 · Finish Filling', endsAt: at, done: false, more: 0,
    alarms: [{ at, title: "Time's up: Rice", body }], checks: [{ at: check, title: 'Check it: Rice', body }],
    check: { at: check, before: 'Check at 1:00', after: 'Check now · up to 0:30 more' },
  }, null)
}

// Android, with no push: the leave-by and start-prep countdowns are scheduled ahead as exact alarms
// from the event list the reminders fetch (src/reminders.ts), on every sync and background refresh,
// so they show with the app closed. They're this device's person's (GET /api/me with the page's
// key: the owner an admin set; the widgets' key may not carry it, so it's kept for later).
const OWNER = 'leaveByOwner'
export async function scheduleLeaveBy(c: Connection, events: LeaveByEvent[]) {
  if (Platform.OS !== 'android' || !KinwallNative) return
  if (device) {
    const me = await api<{ owner: string | null }>(device.baseURL, device.key, 'GET', 'api/me').catch(() => null)
    if (me) await SecureStore.setItemAsync(OWNER, me.owner ?? '').catch(() => {})
  }
  const owner = await SecureStore.getItemAsync(OWNER).catch(() => null)
  const people = owner && owner !== 'shared' ? await api<LeaveByPerson[]>(c.baseURL, c.key, 'GET', 'api/members').catch(() => null) : []
  if (!people) return // offline: the alarms already set stay
  const me = people.find((p) => p.id === owner)
  await KinwallNative.leaveBySchedule(JSON.stringify(me ? leaveByAlarms(events, me, Date.now()) : [])).catch(() => {})
}
