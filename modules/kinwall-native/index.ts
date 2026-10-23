import { type EventSubscription, requireOptionalNativeModule } from 'expo-modules-core'

type KinwallNative = {
  routineStatus?(): Promise<{ simulator: boolean; authorized: boolean; selected: number; appMode?: 'selected' | 'all'; allowedWebsitesOnly?: boolean; locked: boolean; memberId: string }>
  routineSetup?(memberId: string, appMode: 'selected' | 'all', websiteList: boolean): Promise<Record<string, unknown>>
  routineApply?(json: string): Promise<Record<string, unknown>>
  keychainGet(service: string, shared: boolean): Promise<string | null>
  keychainSet(service: string, shared: boolean, value: string | null): Promise<void>
  reloadWidgets(): void
  watchAppInstalled(): boolean
  updateWatch(context: Record<string, unknown>): void
  /** Live Activities (ios/LiveActivities.swift): payload is the web app's JSON for that kind. */
  activitySet(kind: string, payload: string, colors: { bg: string; fg: string; accent: string } | null): Promise<void>
  /** No kind: every one (sign-out). */
  activityEnd(kind: string | null): Promise<void>
  activityEndStale(): Promise<void>
  /** Live Activities allowed in iPhone Settings; on Android, notifications and the countdowns' channel on. */
  activitiesEnabled(): boolean
  /** This signed build carries the APNs entitlement. */
  pushEnabled?(): boolean
  appAttestSupported?(): boolean
  appAttestGenerateKey?(): Promise<string>
  appAttestKey?(key: string, challenge: string): Promise<string>
  appAttestAssertion?(key: string, clientData: string): Promise<string>
  /** iOS: Spotlight's items (src/spotlight.ts), replacing the last set; cleared on sign-out. */
  spotlightSet?(items: { id: string; title: string; description: string; kind: string }[]): Promise<void>
  spotlightClear?(): Promise<void>
  /** iOS: a family.kinwall.app:/open link from Siri or a Control (native/ios/OpenIntents.swift), once. */
  takeLink?(): string | null
  /** Android: the vCard text of a contact shared to the app (plugins/withKinwallNative.js), once. */
  takeSharedContacts?(): string | null
  /** iOS: after src/reminders.ts schedules, sets what expo-notifications can't: the Focus filter's
   * tag (data.focus) and, in a build signed for it, Time Sensitive (data.urgent). */
  tagReminders?(): Promise<void>
  /** Android: the next day's leave-by alarms (src/leaveBy.ts), replacing the last ones. */
  leaveBySchedule(alarms: string): Promise<void>
  /** Android: the notification channels (Channels.kt), before scheduling on them. */
  ensureChannels?(): Promise<void>
  /** Android: a channel's page in Android Settings (e.g. "medicine", to let it through Do Not
   * Disturb); the app's notification settings without one. */
  openNotificationSettings?(channel: string | null): void
  /** Android 13 and later: asks to add a Quick Settings tile ("groceries" or "night"); Android's
   * answer (StatusBarManager TILE_ADD_REQUEST_RESULT_*), -1 where it can't. */
  addTile?(name: string): Promise<number>
  /** Android: a Google Meet video call to a phone number (src/links.ts meetCall), or Meet's Play Store page without it. */
  videoCall?(number: string): void
  /** Android: the navigation bar's buttons light (on a dark page) or dark. */
  navigationBar(dark: boolean): void
  addListener(event: 'watchStateChanged', listener: () => void): EventSubscription
  /** iOS: takeLink() has one. */
  addListener(event: 'link', listener: () => void): EventSubscription
  /** With push (a paid team): a token for the server, PUT /api/live-activities/tokens. */
  addListener(event: 'activityToken', listener: (t: ActivityToken) => void): EventSubscription
}
export type ActivityToken = { kind: 'start' | 'update'; token: string; activity?: string; endsAt?: string }

/** On Android (android/: the keys and the countdowns as ongoing notifications) the widget and Watch
 * calls do nothing: widgets there render from JavaScript (src/widgets.tsx), and there's no Watch. */
export default requireOptionalNativeModule<KinwallNative>('KinwallNative')
