import * as BackgroundTask from 'expo-background-task'
import * as Notifications from 'expo-notifications'
import * as TaskManager from 'expo-task-manager'
import { Platform, Settings } from 'react-native'
import KinwallNative from '../modules/kinwall-native'
import { type Connection, type EventInstance, choresOn, events, me, medicationDay } from './api'
import { choreNudge, doseReminders, focusTag, localAt } from './reminderPlans'
import { widgetConnection } from './sharedKey'
import { endStaleActivities, scheduleLeaveBy } from './liveActivities'
import type { LeaveByEvent } from './leaveBy'

// Event reminders as local notifications (docs/WIDGETS-AND-WATCH.md): the app can't receive the
// server's web push, so it schedules the same reminders itself from the event list, using each
// event's own reminder times (or the household default the server fills in). Rescheduled whenever
// the app opens or goes to the background, and by a background task a few times a day.
const REFRESH_TASK = 'family.kinwall.app.reminders'
const PREFIX = 'rem:'
/** A snoozed copy (native/ios/NotificationActions.swift): a refresh leaves it be; sign-out clears it. */
const SNOOZED = 'snz:'
/** iOS keeps at most 64 pending notifications per app; leave room for anything else. */
const CAP = 60
/** How far ahead to schedule. Refreshes happen well within this. */
const HORIZON = 48 * 3600 * 1000
export const CHANNEL = 'reminders'
/** Android's other channels (modules/kinwall-native/android Channels.kt makes them all). */
const LEAVE_BY = 'leave_by', MEDICINE = 'medicine', CHORES = 'chores'
const IOS = Platform.OS === 'ios'
const ensureChannels = () => (IOS ? undefined : KinwallNative?.ensureChannels?.().catch(() => {}))

// iOS: a cooking timer's notification (modules/kinwall-native/ios/CookingAlarms.swift, id "cook:…")
// stays quiet while the app is open, since cooking mode beeps itself.
Notifications.setNotificationHandler({
  handleNotification: async (n) => {
    const show = !n.request.identifier.startsWith('cook:')
    return { shouldShowBanner: show, shouldShowList: show, shouldPlaySound: show, shouldSetBadge: false }
  },
})

/** Asks once: only while the answer is still unknown. Called on every page load (WebShell's 'key'),
 * and on Android even an answered request opens the system's see-through permission screen,
 * which pauses the app and swallows taps for a moment, and its resume probes the page
 * (WebShell's 'alive'), restarting a page still busy starting up. */
export async function requestPermission(): Promise<void> {
  await ensureChannels()
  const now = await Notifications.getPermissionsAsync().catch(() => null)
  if (now && now.status !== 'undetermined') return
  await Notifications.requestPermissionsAsync().catch(() => {})
}

// The buttons on each kind, run without opening the app with the widgets' key: on iPhone by
// native/ios/NotificationActions.swift, on Android by modules/kinwall-native/android ReminderActions.kt.
const later = { opensAppToForeground: false }
const categories = Promise.all([
  Notifications.setNotificationCategoryAsync('event', [
    { identifier: 'snooze', buttonTitle: 'Snooze 10 min', options: later },
    { identifier: 'open', buttonTitle: 'Open', options: { opensAppToForeground: true } },
  ]),
  Notifications.setNotificationCategoryAsync('medicine', [
    { identifier: 'taken', buttonTitle: 'Taken', options: later },
    { identifier: 'snooze', buttonTitle: 'Snooze 10 min', options: later },
  ]),
  Notifications.setNotificationCategoryAsync('chore', [{ identifier: 'done', buttonTitle: 'Done', options: later }]),
]).catch(() => {})

type Planned = { fire: number; request: Notifications.NotificationRequestInput }

export async function refreshReminders(): Promise<void> {
  const { granted } = await Notifications.getPermissionsAsync()
  const connection = await widgetConnection()
  if (!granted || !connection) return
  const now = Date.now()
  // ponytail: fetch failure keeps the reminders already scheduled; they may be stale until the next refresh.
  const list = await events(connection, new Date(now - 3600_000), new Date(now + HORIZON)).catch(() => null)
  if (!list) return
  await scheduleLeaveBy(connection, list as LeaveByEvent[]) // Android: the leave-by countdowns
  await ensureChannels()
  const person = await me(connection).then((m) => (m.owner && m.owner !== 'shared' ? m.owner : null)).catch(() => null)
  const planned = [...list.flatMap((e) => requestsFor(e, now, person)), ...(person ? await personal(connection, person, now) : [])]
    .sort((a, b) => a.fire - b.fire).slice(0, CAP)
  await categories
  const old = (await Notifications.getAllScheduledNotificationsAsync()).filter((r) => r.identifier.startsWith(PREFIX))
  await Promise.all(old.map((r) => Notifications.cancelScheduledNotificationAsync(r.identifier)))
  for (const p of planned) await Notifications.scheduleNotificationAsync(p.request).catch(() => {})
  await KinwallNative?.tagReminders?.().catch(() => {}) // iOS: the Focus filter's tag, and Time Sensitive where signed
}

/** Sign-out: nothing should fire for a household this device no longer belongs to. */
export async function clearReminders(): Promise<void> {
  const old = (await Notifications.getAllScheduledNotificationsAsync()).filter((r) => r.identifier.startsWith(PREFIX) || r.identifier.startsWith(SNOOZED))
  await Promise.all(old.map((r) => Notifications.cancelScheduledNotificationAsync(r.identifier)))
}

// ---- A person's own phone: medicine reminders and the chore nudge (src/reminderPlans.ts) ----

/** Medicine text stays generic on the Lock Screen: never the medicine's name (the per-device
 * "medicine names" choice lives with the web's push settings, which the app can't read). */
async function personal(c: Connection, person: string, now: number): Promise<Planned[]> {
  const out: Planned[] = []
  const meds = await medicationDay(c, person).catch(() => null) // 404: the family has medicines off
  for (const d of meds ? doseReminders(meds, now) : []) {
    if (d.at <= now || d.at > now + HORIZON) continue
    out.push(at(d.at, `${PREFIX}med:${d.medicationId}:${d.date}:${d.time}`, 'medicine', MEDICINE, 'Time for your medicine', `${time(new Date(d.at))} dose`,
      { route: 'calendar', medicationId: d.medicationId, date: d.date, time: d.time, urgent: true }))
  }
  // The chore nudge: off unless turned on, in iPhone Settings → Kinwall (native/ios/Settings.bundle),
  // or on Android by turning on its channel, Chores, which starts off (Channels.kt); 8:00 AM there.
  if (await choreNudgeOn()) {
    const hhmm = IOS ? String(Settings.get('choreNudgeTime') ?? '08:00') : '08:00'
    for (const offset of [0, 1]) {
      const date = localDay(now, offset)
      const fire = localAt(date, hhmm)
      if (fire <= now) continue
      const nudge = choreNudge(await choresOn(c, date).catch(() => []), person)
      if (nudge) out.push(at(fire, `${PREFIX}chore:${date}`, nudge.choreId ? 'chore' : undefined, CHORES, nudge.title, nudge.body, { route: 'chores', choreId: nudge.choreId, date }))
    }
  }
  return out
}

async function choreNudgeOn(): Promise<boolean> {
  if (IOS) return !!Settings.get('choreNudge')
  const channel = await Notifications.getNotificationChannelAsync(CHORES).catch(() => null)
  return !!channel && channel.importance > Notifications.AndroidImportance.NONE
}

/** `channelId`: Android's channel; iOS has none. */
function at(fire: number, identifier: string, category: string | undefined, channelId: string, title: string, body: string, data: Record<string, unknown>): Planned {
  return { fire, request: { identifier, content: { title, body, sound: 'default', data, categoryIdentifier: category }, trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: fire, channelId } } }
}

/** The device's YYYY-MM-DD, `days` from now. */
function localDay(now: number, days: number): string {
  const d = new Date(now)
  d.setDate(d.getDate() + days)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// A few times a day, so reminders for events added elsewhere are scheduled even if the app isn't
// opened. Android runs it every 15 minutes (WorkManager's shortest, with a network), since the
// leave-by alarms are only as fresh as the last run; signed out it stops at the missing key.
TaskManager.defineTask(REFRESH_TASK, async () => {
  await refreshReminders()
  endStaleActivities() // a leave-by whose event started while the app was closed
  return BackgroundTask.BackgroundTaskResult.Success
})
export const scheduleBackgroundRefresh = () => BackgroundTask.registerTaskAsync(REFRESH_TASK, { minimumInterval: Platform.OS === 'android' ? 15 : 240 }).catch(() => {})

// ---- Building them (mirrors the server's reminder text in server/src/notify.ts) ----

const time = (d: Date) => d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })

function requestsFor(e: EventInstance, now: number, person: string | null): Planned[] {
  if (!e.reminders?.length) return []
  // ponytail: all-day events start at midnight in the device's timezone, not the household's; differs only when the phone travels.
  const start = e.allDay ? localMidnight(e.start) : Date.parse(e.start)
  if (Number.isNaN(start)) return []
  const leave = e.remindBeforeLeave && e.leaveAt ? Date.parse(e.leaveAt) : null
  const anchor = leave ?? start
  const timeText = e.allDay ? 'All day' : time(new Date(start))
  const out: Planned[] = []
  const focus = focusTag(e.memberIds, person)
  for (const m of e.reminders) {
    const fire = anchor - m * 60_000
    if (fire <= now || fire > now + HORIZON) continue
    const first = leave != null ? `Leave by ${time(new Date(leave))} for ${e.title} · starts ${timeText}` : `${when(m)} · ${timeText}`
    const body = [first, e.location ? `📍 ${e.location.replace(/\n/g, ', ')}` : null].filter(Boolean).join('\n')
    const route = `calendar?event=${encodeURIComponent(e.id)}&at=${encodeURIComponent(e.start)}` // tap opens this event
    out.push({
      fire,
      request: {
        identifier: `${PREFIX}${e.id}:${e.start}:${m}`,
        // Snooze / Open; on iPhone a leave-by breaks through Focus where the build can (Time
        // Sensitive), on Android it goes on the Leave-by channel.
        content: { title: e.title, body, sound: 'default', data: { route, focus, urgent: leave != null }, categoryIdentifier: 'event' },
        trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: fire, channelId: leave != null ? LEAVE_BY : CHANNEL },
      },
    })
  }
  return out
}

function when(m: number): string {
  if (m === 0) return 'Now'
  if (m % 60 === 0) return `In ${m / 60} hour${m === 60 ? '' : 's'}`
  return `In ${m} minute${m === 1 ? '' : 's'}`
}

function localMidnight(day: string): number {
  const [y, mo, d] = day.split('-').map(Number)
  return y && mo && d ? new Date(y, mo - 1, d).getTime() : NaN
}
