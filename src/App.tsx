import * as Linking from 'expo-linking'
import * as Notifications from 'expo-notifications'
import * as WebBrowser from 'expo-web-browser'
import { useCallback, useEffect, useRef, useState } from 'react'
import { AppState, Platform } from 'react-native'
import * as SplashScreen from 'expo-splash-screen'
import { StatusBar } from 'expo-status-bar'
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context'
import type { Tokens } from './oauth'
import { DEMO_URL, enterDemo, leaveDemo } from './demo'
import { refreshReminders, scheduleBackgroundRefresh } from './reminders'
import { clearServer, loadServer, saveServer } from './server'
import { ServerEntry } from './ServerEntry'
import { type Session, freshTokens, loadSession, signOut } from './session'
import { syncWatch, widgetConnection } from './sharedKey'
import { groceriesRoute, routeFor } from './links'
import { isProviderReturn, providerReturnUrl } from './providerReturn'
import { type Features, features, lists } from './api'
import { pickGroceries } from './widgetData'
import { showSampleCooking, showSampleMedication } from './liveActivities'
import { syncSpotlight } from './spotlight'
import { endAllActivities, endStaleActivities } from './liveActivities'
import { SignIn } from './SignIn'
import { WebShell } from './WebShell'
import { hideSplash, useUi } from './theme'
import KinwallNative from '../modules/kinwall-native'

// The launch screen stays up until the saved session is known and what's under it has painted
// (hideSplash), so a signed-in launch never shows the sign-in screen or the app's own colors.
SplashScreen.preventAutoHideAsync().catch(() => {})

/** The phone and tablet app: the household's own Kinwall web app, full screen, in a native frame
 * (docs/PLAN.md). First launch asks for the server, then signs in (OAuth in the system's auth
 * sheet, or a pairing code). */

export default function App() {
  const [server, setServer] = useState<string | null | undefined>() // undefined: still loading
  const [session, setSession] = useState<Session>(null)
  const [route, setRoute] = useState<string | null>(null) // a tab to show, from a widget link or a reminder
  const url = Linking.useURL()
  const ui = useUi()
  const tapped = Notifications.useLastNotificationResponse()

  // The demo is never saved, so a fresh launch clears anything it left for the widgets and reminders.
  // The saved server and sign-in come from the Keychain, which refuses while the phone is locked:
  // iOS can start the app in the background then (its reminder refresh), and the first read failing
  // left a blank screen until the app was closed. So a failed read tries again when it's opened.
  useEffect(() => {
    leaveDemo()
    let done = false
    const load = () => { if (!done) loadServer().then(async (s) => { const ses = s ? await launchSession(s) : null; done = true; setSession(ses); setServer(s) }).catch(() => {}) }
    load()
    const sub = AppState.addEventListener('change', (s) => { if (s === 'active') load() })
    return () => sub.remove()
  }, [])
  // The native screens (address, sign-in) are ready as soon as they're shown; the web view hides
  // the launch screen itself once the page has painted (src/WebShell.tsx).
  useEffect(() => { if (server === null || (server && !session)) hideSplash() }, [server, session])

  // Widget links: family.kinwall.app:/open?to=chores (or calendar, lists), plus &done=<chore id>
  // to tap that chore in the web app (it asks "Who did it?" or opens the checklist); and what the
  // share sheet added (to=shared&link=…), to check it.
  useEffect(() => { if (url) { if (__DEV__ && url.includes('debug=medication')) showSampleMedication(); if (__DEV__ && url.includes('debug=cooking')) showSampleCooking(); const r = routeFor(url); if (r) resolve(r).then(setRoute) } }, [url])
  // A Google/Microsoft sign-in handed back from the in-app browser (src/providerReturn.ts): close
  // that browser (iOS; Android brings the app forward over its Custom Tab) and finish it in the web
  // view, on this app's own server. Each link once (the session changes on every token refresh).
  // Signed out or in the demo there's no web view that started it, so it's dropped.
  const handled = useRef<string | null>(null)
  useEffect(() => {
    if (!url || server === undefined || handled.current === url || !isProviderReturn(url)) return
    handled.current = url
    if (Platform.OS === 'ios') WebBrowser.dismissBrowser().catch(() => {})
    const callback = server && session && session.mode !== 'demo' ? providerReturnUrl(url, server) : null
    if (callback) setRoute(callback)
  }, [url, server, session])
  // Siri and the Controls (native/ios/OpenIntents.swift) leave their link with the native module:
  // take it at launch, when told, and on every return to the app.
  useEffect(() => {
    const take = () => { const l = KinwallNative?.takeLink?.(); const r = l ? routeFor(l) : null; if (r) resolve(r).then(setRoute) }
    take()
    const sub = KinwallNative?.addListener('link', take)
    const active = AppState.addEventListener('change', (s) => { if (s === 'active') take() })
    return () => { sub?.remove(); active.remove() }
  }, [])
  // A tapped reminder, or its Open, opens its event; its other buttons (Snooze, Taken, Done) run
  // natively without opening the page (native/ios/NotificationActions.swift).
  useEffect(() => {
    if (tapped && tapped.actionIdentifier !== Notifications.DEFAULT_ACTION_IDENTIFIER && tapped.actionIdentifier !== 'open') return
    const r = tapped?.notification.request.content.data?.route
    if (typeof r === 'string') setRoute(r)
  }, [tapped])

  // Reminders are rescheduled each time the app opens or goes to the background; Spotlight follows
  // the family's recipes, lists and contacts (src/spotlight.ts).
  useEffect(() => {
    refreshReminders(); endStaleActivities(); syncSpotlight()
    const sub = AppState.addEventListener('change', (s) => { if (s === 'background') scheduleBackgroundRefresh(); if (s === 'active') { refreshReminders(); endStaleActivities(); syncSpotlight() } })
    const watch = KinwallNative?.addListener('watchStateChanged', () => { syncWatch() }) // e.g. the Watch app was just installed
    return () => { sub.remove(); watch?.remove() }
  }, [])

  // Leaving the demo is the same as changing server: back to the first screen (the demo was never
  // saved), with its sample widgets and reminders cleared (src/demo.ts).
  const changeServer = useCallback(async () => { endAllActivities(); if (session?.mode === 'demo') await leaveDemo(); else { await signOut(session); await clearServer() } setSession(null); setServer(null) }, [session])
  const signedOut = useCallback(async () => { if (session?.mode === 'demo') { await leaveDemo(); setSession(null); setServer(null); return } await signOut(session); setSession(null) }, [session])
  const tryDemo = useCallback(() => { setSession({ mode: 'demo' }); setServer(DEMO_URL); enterDemo() }, [])
  const onTokens = useCallback((tokens: Tokens) => setSession({ mode: 'oauth', tokens }), [])
  const routeApplied = useCallback(() => setRoute(null), [])

  return (
    <SafeAreaProvider>
      {server === undefined ? null
        : !server ? <SafeAreaView style={ui.root}><StatusBar style={ui.dark ? 'light' : 'dark'} /><ServerEntry onConnect={async (u) => { await leaveDemo(); await saveServer(u); setServer(u) }} onDemo={tryDemo} /></SafeAreaView>
        : !session ? <SafeAreaView style={ui.root}><StatusBar style={ui.dark ? 'light' : 'dark'} /><SignIn server={server} onSession={setSession} onChangeServer={changeServer} /></SafeAreaView>
        : <WebShell url={server} session={session} route={route} onRouteApplied={routeApplied} onTokens={onTokens} onSignedOut={signedOut} onChangeServer={changeServer} />}
    </SafeAreaProvider>
  )
}

/** Android's shortcuts and tiles ask for "groceries": the family's Groceries list, found with the
 * widgets' key (src/widgetData.ts pickGroceries); Lists signed out, offline or in the demo; the
 * calendar when the family turned Lists off. */
async function resolve(route: string): Promise<string> {
  if (route !== 'groceries' && route !== 'groceries/shop') return route
  const c = await widgetConnection()
  const [groceries, f] = await Promise.all([c ? lists(c).then(pickGroceries).catch(() => null) : null, c ? features(c) : ({} as Features)])
  if (f.lists === false) return 'calendar'
  return groceriesRoute(route, groceries?.id)
}

/** The saved session, with OAuth keys refreshed first if they've lapsed (they last an hour): the
 * page would otherwise start with a dead key, get a 401 and flash its pairing screen before the
 * app caught up. Offline keeps the old key (freshTokens); a grant that's gone means sign in. */
async function launchSession(server: string): Promise<Session> {
  const s = await loadSession(server)
  if (s?.mode !== 'oauth') return s
  // A slow network doesn't hold the launch: past a few seconds, carry on with the old key (the
  // page's 401 comes back to WebShell, which refreshes and reloads).
  const tokens = await Promise.race([freshTokens(s.tokens), new Promise<Tokens>((r) => setTimeout(() => r(s.tokens), 4000))])
  return tokens ? { mode: 'oauth', tokens } : null
}
