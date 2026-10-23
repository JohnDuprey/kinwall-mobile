import * as WebBrowser from 'expo-web-browser'
import Constants from 'expo-constants'
import { activateKeepAwakeAsync, deactivateKeepAwake } from 'expo-keep-awake'
import { StatusBar } from 'expo-status-bar'
import * as SecureStore from 'expo-secure-store'
import { useEffect, useRef, useState } from 'react'
import { AppState, BackHandler, Dimensions, Linking, Platform, Pressable, StyleSheet, Text, View, useColorScheme } from 'react-native'
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context'
import { WebView, type WebViewMessageEvent } from 'react-native-webview'
import type { Tokens } from './oauth'
import { doseChanged, refreshReminders, requestPermission } from './reminders'
import { nativePushAvailable, onNativePushChange, savedNativePush, setNativePushEnabled, syncNativePush } from './nativePush'
import { type Surface, activityColors, frameColors, parseAppearance } from './appearance'
import { activitiesEnabled, endActivity, endAllActivities, setActivityDevice, setLeaveByPush, showActivity } from './liveActivities'
import * as Notifications from 'expo-notifications'
import { hideSplash, saveAppearance, savedAppearance, useUi } from './theme'
import { type Session, freshTokens, needsRefresh } from './session'
import { ensureWidgetKey, shareKey, syncWatch, widgetConnection } from './sharedKey'
import { reloadWidgets } from './widgets'
import { syncSpotlight } from './spotlight'
import KinwallNative from '../modules/kinwall-native'
import * as Crypto from 'expo-crypto'
import * as Speech from 'expo-speech'
import { setAudioModeAsync, setIsAudioActiveAsync } from 'expo-audio'
import { backAction, bridgeMessage, sameDocument, sameOrigin } from './bridge'
import { importContactsScript, meetCall } from './links'
import { barcodeScript, scanFacing } from './barcode'
import { Scanner } from './Scanner'
import { createLoadRecovery, createPageProbe } from './loadRecovery'
import { refreshRoutine, setRoutineConnection, setupRoutine, syncRoutine } from './routineController'
import { routineRequest } from './routineMode'
import { readStatusBarHidden, saveStatusBarHidden, statusBarMessage, statusBarScript, statusBarSurface } from './statusBar'

// Web pages open in an in-app browser: handing them to the system lets another app claim the link
// (the GitHub app drops ?template=, so both Help forms landed on the same page). Maps and
// non-web links (mailto:, tel:) still go to the system so their apps open.
const MAPS = /^https?:\/\/(maps\.apple\.com|maps\.google\.|www\.google\.[^/]+\/maps)/
// The contact sheet's Video call (intent:… for Google Meet) goes to the native module: an intent:
// link isn't a URL Linking can open.
function openOutside(url: string) {
  const meet = meetCall(url)
  if (meet) { KinwallNative?.videoCall?.(meet); return }
  if (/^https?:/.test(url) && !MAPS.test(url)) WebBrowser.openBrowserAsync(url).catch(() => Linking.openURL(url).catch(() => {}))
  else Linking.openURL(url).catch(() => {})
}

const isTablet = Platform.OS === 'ios' ? Platform.isPad : Math.min(Dimensions.get('screen').width, Dimensions.get('screen').height) >= 600
const VERSION = Constants.expoConfig?.version ?? '0'
// Per launch: the main-frame shim adds it to every message, and onMessage drops any without it (src/bridge.ts).
const NONCE = Array.from(Crypto.getRandomValues(new Uint8Array(16)), (b) => b.toString(16).padStart(2, '0')).join('')

/** Read by the web app to adapt (hide the Add to Home Screen card and web push, which don't
 * apply inside the app). `providerReturn`: this app finishes a Google/Microsoft sign-in handed back
 * from the in-app browser (src/providerReturn.ts); the web app asks an app without it to update
 * before connecting one. Keep in sync with web/src/native.ts in the kinwall repo, which posts to
 * webkit.messageHandlers.kinwall: that's shimmed onto the WebView's own channel here.
 * `frame`: the family's last colors (src/appearance.ts), put on <html> before anything paints so
 * the page's first frame ("Loading…") is already in them; the page's own theme takes over once
 * its settings load (web/src/useTheme.ts). */
const bridge = (origin: string, token: string | null, frame: (Surface & { dark: boolean }) | null, push: boolean, statusBarHidden: boolean) => `
window.kinwallNative = { platform: ${JSON.stringify(Platform.OS)}, version: ${JSON.stringify(VERSION)}, providerReturn: true, nativePush: ${JSON.stringify(push)}, liveActivities: ${JSON.stringify(activitiesEnabled())}, notificationSettings: ${JSON.stringify(Platform.OS === 'android')}, quickSettingsTiles: ${JSON.stringify(Platform.OS === 'android' && Number(Platform.Version) >= 33)}, videoCall: ${JSON.stringify(Platform.OS === 'android')}, barcodeScanner: true, speech: true, statusBar: true, statusBarHidden: ${JSON.stringify(statusBarHidden)} };
${token ? `if (location.origin === ${JSON.stringify(origin)}) try { localStorage.setItem('kinwall.apiKey', ${JSON.stringify(token)}) } catch (e) {}` : ''}
${frame ? `try { var r = document.documentElement; r.setAttribute('data-theme', ${JSON.stringify(frame.dark ? 'dark' : 'light')}); r.style.setProperty('--bg', ${JSON.stringify(frame.bg)}); r.style.setProperty('--card', ${JSON.stringify(frame.card)}) } catch (e) {}` : ''}
(function () {
  // The nonce stays in this closure: only this main-frame shim has it (src/bridge.ts).
  var nonce = ${JSON.stringify(NONCE)};
  var post = function (m) { var o = {}; for (var k in m) o[k] = m[k]; o.nonce = nonce; window.ReactNativeWebView.postMessage(JSON.stringify(o)) };
  var kinwall = { postMessage: post };
  // Our handler goes on WebKit's messageHandlers object, which loses added properties when its
  // wrapper is garbage-collected: holding references keeps it (window.webkit can't be replaced).
  try {
    var ns = window.webkit;
    if (ns && ns.messageHandlers) {
      Object.defineProperty(ns.messageHandlers, 'kinwall', { value: kinwall });
      window.__kinwallHold = [ns, ns.messageHandlers];
    } else window.webkit = { messageHandlers: { kinwall: kinwall } }; // Android
  } catch (e) {}
  var last = '';
  var theme = function () {
    var m = document.querySelector('meta[name="theme-color"]');
    if (m && m.content && m.content !== last) { last = m.content; post({ type: 'theme', color: m.content }) }
  };
  new MutationObserver(theme).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['content'] });
})();
true;`

type Props = {
  url: string
  session: NonNullable<Session>
  route: string | null
  onRouteApplied: () => void
  onTokens: (t: Tokens) => void
  onSignedOut: () => void
  onChangeServer: () => void
}

/** The Kinwall web app, full screen. Tells the page it's inside the app, keeps other sites in
 * the browser, follows the page's theme color, and hands the paired key to the widgets, Watch and Siri. */
export function WebShell({ url, session, route, onRouteApplied, onTokens, onSignedOut, onChangeServer }: Props) {
  const web = useRef<WebView>(null)
  const ui = useUi()
  const insets = useSafeAreaInsets()
  const systemDark = useColorScheme() === 'dark'
  const [statusBarHidden, setStatusBarHidden] = useState(() => readStatusBarHidden(SecureStore))
  // The family's colors from last time (never the demo's), so the frame starts in them; updated
  // live from the page. `theme` is the older servers' meta theme-color, used until then.
  const [look, setLook] = useState(() => (session.mode === 'demo' ? null : savedAppearance()))
  const frame = frameColors(look, systemDark)
  const [theme, setTheme] = useState<string | null>(null)
  const [failed, setFailed] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [startsPairing, setStartsPairing] = useState<boolean | null>(null)
  const [scanning, setScanning] = useState<'front' | 'back' | null>(null) // the camera the scanner opens with
  const pending = useRef<string | null>(null)
  const canGoBack = useRef(false)
  const origin = new URL(url).origin
  useEffect(() => {
    setRoutineConnection(null, session.mode === 'demo')
    const timer = setInterval(() => { if (AppState.currentState === 'active') refreshRoutine() }, 15000)
    const sub = AppState.addEventListener('change', s => { if (s === 'active') refreshRoutine() })
    return () => { clearInterval(timer); sub.remove(); setRoutineConnection(null) }
  }, [url, session.mode])
  const token = session.mode === 'oauth' ? session.tokens.accessToken : null
  useEffect(() => {
    web.current?.injectJavaScript(`if (location.origin === ${JSON.stringify(origin)}) { ${statusBarScript(statusBarHidden)} } true;`)
  }, [statusBarHidden, origin])

  // The page can go blank under the app: iOS ends a background web view's process to free memory
  // (it comes back white), Android's renderer can go, a script can fail to load at launch. So the
  // app asks the page (on every return, and once it has loaded) and starts a fresh web view where it
  // was if it doesn't answer or drew nothing. `here`: its last URL, with its #/ route.
  const [mount, setMount] = useState<{ n: number; at: string | null }>({ n: 0, at: null })
  const here = useRef<string | null>(null)
  // The web view's current URL, to tell a real page load from a #/ route change (sameDocument).
  const pageUrl = useRef<string | null>(null)
  const blankRestarts = useRef(0)
  const loadCheck = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  // Where the page is now, from every navigation (a tab tap only changes its #/ route) as well as its
  // messages: a restart used to reopen the last page that had posted a message, often Home, so
  // coming back from the share sheet or the scanner (a probe that timed out) lost the open list.
  const track = (u: string) => { pageUrl.current = u; if (isKinwall(u)) here.current = u }
  const restart = (at?: string) => {
    clearTimeout(loadCheck.current)
    pageProbe.cancel()
    loadRecovery.cancel()
    pageUrl.current = null
    setFailed(null)
    setLoading(true)
    setMount((m) => ({ n: m.n + 1, at: at && isKinwall(at) ? at : here.current }))
  }
  // The controllers keep their timers across renders, with current callbacks.
  const restartRef = useRef(restart)
  restartRef.current = restart
  const [pageProbe] = useState(() => createPageProbe({
    active: () => AppState.currentState === 'active',
    restart: () => restartRef.current(),
    schedule: (run, delay) => setTimeout(run, delay), cancel: clearTimeout,
    send: (id) => web.current?.injectJavaScript(`try { var r = document.getElementById('root'); window.webkit.messageHandlers.kinwall.postMessage({ type: 'alive', probe: ${id}, blank: !!r && !r.firstElementChild }) } catch (e) {} true;`),
  }))
  const [loadRecovery] = useState(() => createLoadRecovery({
    platform: Platform.OS,
    active: () => AppState.currentState === 'active',
    restart: () => restartRef.current(), fail: setFailed,
    schedule: (run, delay) => setTimeout(run, delay), cancel: clearTimeout,
  }))
  const probe = () => { if (web.current) pageProbe.start() }
  useEffect(() => {
    const sub = AppState.addEventListener('change', (s) => {
      if (s !== 'active') { clearTimeout(loadCheck.current); pageProbe.cancel(); return }
      loadRecovery.resume()
      if (!loading && !failed) probe()
    })
    return () => sub.remove()
  }, [loading, failed, pageProbe, loadRecovery])
  useEffect(() => () => { clearTimeout(loadCheck.current); pageProbe.cancel(); loadRecovery.dispose() }, [pageProbe, loadRecovery])
  useEffect(() => {
    if (!failed) return
    clearTimeout(loadCheck.current)
    pageProbe.cancel()
    loadRecovery.cancel()
  }, [failed, pageProbe, loadRecovery])
  // A refreshed key reaches the page through the bridge script, so reload only once it has the new one.
  const reloadOnToken = useRef(false)
  const lastRejected = useRef(0)
  useEffect(() => { if (reloadOnToken.current) { reloadOnToken.current = false; web.current?.reload() } }, [token])

  useEffect(() => {
    if (!token) return
    const c = { baseURL: url, key: token }
    setActivityDevice(c)
    syncNativePush(c).catch(() => {})
  }, [url, token])

  // The launch screen waits for the page (onLoadEnd, its look, or a failed load), but not forever.
  useEffect(() => { const t = setTimeout(hideSplash, 3000); return () => clearTimeout(t) }, [])

  // A wall tablet stays awake; a phone sleeps as usual.
  useEffect(() => {
    if (!isTablet) return
    activateKeepAwakeAsync('wall').catch(() => {})
    return () => { deactivateKeepAwake('wall').catch(() => {}) }
  }, [])

  // Chose "Pair with a code": open the page on its pairing code (web/src/App.tsx reads ?start=pair).
  useEffect(() => { widgetConnection().then((c) => setStartsPairing(session.mode === 'paired' && !c), () => setStartsPairing(false)) }, [session.mode])

  // OAuth keys last an hour: refresh ahead of time while the app is open, and on every return.
  useEffect(() => {
    if (session.mode !== 'oauth') return
    let timer: ReturnType<typeof setInterval> | undefined
    const tick = async () => {
      if (AppState.currentState !== 'active' || !needsRefresh(session.tokens)) return
      const next = await freshTokens(session.tokens)
      if (!next) { onSignedOut(); return }
      onTokens(next)
      web.current?.injectJavaScript(`if (location.origin === ${JSON.stringify(origin)}) localStorage.setItem('kinwall.apiKey', ${JSON.stringify(next.accessToken)}); true;`)
    }
    timer = setInterval(tick, 60_000)
    const sub = AppState.addEventListener('change', (s) => { if (s === 'active') tick() })
    return () => { clearInterval(timer); sub.remove() }
  }, [session, onTokens, onSignedOut])

  // The push subscription id and availability are metadata only; the APNs token stays native.
  useEffect(() => {
    const update = () => {
      const r = savedNativePush()
      const mine = r?.baseURL === url ? r : null
      web.current?.injectJavaScript(`if (location.origin === ${JSON.stringify(origin)} && window.kinwallNative) { window.kinwallNative.pushReady = ${JSON.stringify(mine?.push ?? false)}; ${mine ? `localStorage.setItem('kinwall.pushSubId', ${JSON.stringify(mine.id)});` : `localStorage.removeItem('kinwall.pushSubId');`} window.dispatchEvent(new Event('kinwallnative')); } true;`)
    }
    update()
    return onNativePushChange(update)
  }, [url, origin])

  // Live Activities may have been turned on or off in iPhone Settings meanwhile: tell the page. A
  // leave-by held back for want of notifications shows once they're allowed (the page sends it once).
  const heldLeaveBy = useRef<unknown>(null)
  const frameNow = useRef(frame)
  frameNow.current = frame
  useEffect(() => {
    const sub = AppState.addEventListener('change', async (s) => {
      if (s !== 'active') return
      web.current?.injectJavaScript(`try { window.kinwallNative.liveActivities = ${JSON.stringify(activitiesEnabled())}; window.dispatchEvent(new Event('kinwallnative')) } catch (e) {} true;`)
      syncNativePush().catch(() => {}).finally(() => refreshReminders().catch(() => {}))
      if (heldLeaveBy.current && (await Notifications.getPermissionsAsync()).granted) showActivity('leaveBy', heldLeaveBy.current, activityColors(frameNow.current))
    })
    return () => sub.remove()
  }, [])

  // A tab to show (a widget link or a tapped reminder): once the page is up.
  useEffect(() => {
    if (!route) return
    if (loading) { pending.current = route } else { go(route) }
    onRouteApplied()
  }, [route, loading, onRouteApplied])

  // Android: Back asks the page first (a cancelable 'kinwall:back' on window, which web/src closes
  // an open sheet or dialog with), then goes back in the web app's history, else leaves. The page
  // answers with a 'back' message (onMessage); an older page without the listener answers
  // handled: false. No answer (a page still starting, or stuck) falls back after a moment.
  const backTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const back = (handled: boolean) => {
    clearTimeout(backTimer.current); backTimer.current = undefined
    const a = backAction(handled, canGoBack.current)
    if (a === 'goBack') web.current?.goBack()
    else if (a === 'exit') BackHandler.exitApp()
  }
  const backRef = useRef(back)
  backRef.current = back
  const failedNow = useRef(failed)
  failedNow.current = failed
  useEffect(() => {
    if (Platform.OS !== 'android') return
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (!web.current || failedNow.current) return false // the error screen: leave, as before
      if (backTimer.current) return true // still waiting on the page's answer to the last press
      backTimer.current = setTimeout(() => backRef.current(false), 1500)
      web.current.injectJavaScript(`try { var h = !window.dispatchEvent(new CustomEvent('kinwall:back', { cancelable: true })); window.webkit.messageHandlers.kinwall.postMessage({ type: 'back', handled: h }) } catch (e) {} true;`)
      return true
    })
    return () => { sub.remove(); clearTimeout(backTimer.current) }
  }, [])

  // 'night' (Siri, Control Center): the event the header's 🌙 Night screen button sends (web/src/Screensaver.tsx SAVER_START_EVENT).
  // 'contacts/import' (Android's share sheet): the shared vCard MainActivity left with the native module.
  // A full URL on this server (a provider sign-in's callback, src/providerReturn.ts): load it here.
  const go = (to: string) => web.current?.injectJavaScript(/^https?:/.test(to) ? (isKinwall(to) ? `location.href = ${JSON.stringify(to)}; true;` : 'true;')
    : to === 'night'
    ? `window.dispatchEvent(new Event('kinwall:screensaver-start')); true;`
    : to === 'contacts/import' ? importContactsScript(KinwallNative?.takeSharedContacts?.())
    : `location.hash = ${JSON.stringify('#/' + to)}; true;`)
  const isKinwall = (u: string) => sameOrigin(u, url)

  // What the last 'key' synced (server and key): Android ends a load on every tab tap, so the same
  // key comes back each time; only a new one (or the first) redoes the widgets, reminders, Watch and Spotlight.
  const synced = useRef<string | null>(null)

  /** Once the page is signed in (its key is in localStorage 'kinwall.apiKey'), make sure the widgets have their own key. */
  const syncKey = () => web.current?.injectJavaScript(`try { window.webkit.messageHandlers.kinwall.postMessage({ type: 'key', key: localStorage.getItem('kinwall.apiKey') }) } catch (e) {} true;`)

  const onMessage = async (e: WebViewMessageEvent) => {
    const m = bridgeMessage(e.nativeEvent.data, NONCE, e.nativeEvent.url, url) as { type?: string; reason?: string; color?: string; key?: string | null; on?: boolean; kind?: unknown; payload?: unknown; channel?: unknown; tile?: unknown; facing?: unknown; blank?: boolean; probe?: unknown; handled?: unknown; id?: unknown; text?: unknown; rate?: unknown; lang?: unknown } | null
    if (!m || (m.type === 'alive' && !pageProbe.answer(m.probe))) return
    here.current = e.nativeEvent.url
    switch (m.type) {
      case 'routineMode': {
        const request = routineRequest(m)
        if (!request) break
        let status: unknown
        try { status = request.action === 'setup' ? await setupRoutine(request.memberId) : await syncRoutine(request.memberId, m.payload) }
        catch (e) { status = { error: e instanceof Error ? e.message : String(e) } }
        web.current?.injectJavaScript(`window.dispatchEvent(new CustomEvent('kinwall:routine', { detail: ${JSON.stringify(status)} })); true;`)
        break
      }
      case 'alive': // probe(): a page that drew nothing gets two fresh starts, then the error screen
        if (!m.blank) { blankRestarts.current = 0; loadRecovery.loaded() }
        else if (blankRestarts.current++ < 2) restart()
        else { blankRestarts.current = 0; setFailed("Kinwall didn't finish loading.") }
        break
      case 'back': if (backTimer.current) back(m.handled === true); break // Android's Back, answered (above)
      case 'theme': if (m.color) setTheme(m.color); break
      case 'statusBar': {
        const hidden = statusBarMessage(m)
        if (hidden !== null && saveStatusBarHidden(SecureStore, hidden)) setStatusBarHidden(hidden)
        break
      }
      case 'appearance': { // web/src/native.ts: the page's look changed
        const a = parseAppearance(m)
        if (a) { loadRecovery.loaded(); setLook(a); if (session.mode !== 'demo') saveAppearance(a) }
        hideSplash()
        break
      }
      case 'signedIn': syncKey(); break
      case 'doseChanged': if (session.mode !== 'demo') await doseChanged(m.payload).catch(() => {}); break
      // Shopping mode (web/src/native.ts) keeps the screen on while you shop.
      case 'leaveDemo': if (session.mode === 'demo') onChangeServer(); break // web/src/native.ts: the demo bar's Leave demo
      case 'keepAwake': (m.on ? activateKeepAwakeAsync('shop') : deactivateKeepAwake('shop')).catch(() => {}); break
      // web/src/native.ts: a cooking timer, a shopping trip or the next leave-by, as a Live Activity.
      // A leave-by follows the reminders: none without notifications allowed.
      case 'activity':
        if (m.kind === 'leaveBy') { heldLeaveBy.current = m.payload; if (!(await Notifications.getPermissionsAsync()).granted) break }
        showActivity(m.kind, m.payload, activityColors(frame)); break
      case 'activityEnd': if (m.kind === 'leaveBy') heldLeaveBy.current = null; endActivity(m.kind); break
      // web/src/native.ts: whether this device's person gets transition reminders (and so the leave-by push).
      case 'leaveByPush':
        if (session.mode !== 'demo') setLeaveByPush(!!m.on && (await Notifications.getPermissionsAsync()).granted)
        break
      // Android (window.kinwallNative.notificationSettings): a channel's page in Android Settings, e.g.
      // "medicine" to let it through Do Not Disturb (modules/kinwall-native/android Channels.kt).
      case 'notificationSettings': KinwallNative?.openNotificationSettings?.(typeof m.channel === 'string' ? m.channel : null); break
      // Android 13+ (window.kinwallNative.quickSettingsTiles): offer the "groceries" or "night" tile.
      case 'addTile': if (typeof m.tile === 'string') KinwallNative?.addTile?.(m.tile).catch(() => {}); break
      // web/src/native.ts (window.kinwallNative.barcodeScanner): the camera, for a book's ISBN; the answer is a 'kinwall:barcode' event.
      case 'scanBarcode': setScanning(scanFacing(m)); break
      // web/src/native.ts (window.kinwallNative.speech): say a word for an activity plugin (Kinwall.speak).
      // Android's WebView has no Web Speech, so the system voice speaks; the page hears 'spoken' back.
      case 'speak': {
        if (typeof m.text !== 'string') break
        const id = JSON.stringify(m.id ?? null), text = m.text.slice(0, 500)
        // iOS: the phone's audio only while it talks. Music elsewhere ducks (not pauses) and comes back
        // up when the last word is done and the audio is let go.
        const done = () => {
          if (Platform.OS === 'ios') Speech.isSpeakingAsync().then(more => { if (!more) return setIsAudioActiveAsync(false) }).catch(() => {})
          web.current?.injectJavaScript(`window.dispatchEvent(new CustomEvent('kinwall-native', { detail: { type: 'spoken', id: ${id} } })); true;`)
        }
        const rate = typeof m.rate === 'number' && m.rate > 0 && m.rate <= 2 ? m.rate : 1
        const say = () => Speech.speak(text, { rate, language: typeof m.lang === 'string' ? m.lang : 'en-US', useApplicationAudioSession: true, onDone: done, onStopped: done, onError: done })
        if (Platform.OS === 'ios') setAudioModeAsync({ playsInSilentMode: true, interruptionMode: 'duckOthers' }).catch(() => {}).then(say)
        else say()
        break
      }
      case 'stopSpeaking': Speech.stop(); break
      case 'signedOut': // web/src/native.ts: the page cleared its key
        // `rejected` (a 401): after a sleep the OAuth key may simply have lapsed, so refresh it (even
        // if it looks current: the server just turned it down) and carry on. Turned down again
        // within a minute: say so rather than reload forever.
        if (m.reason === 'rejected' && session.mode === 'oauth') {
          const again = Date.now() - lastRejected.current < 60_000
          lastRejected.current = Date.now()
          if (again) { setFailed("Kinwall didn't accept this phone's sign-in."); return }
          const next = await freshTokens(session.tokens, true)
          if (next) { reloadOnToken.current = true; onTokens(next); if (next.accessToken === token) { reloadOnToken.current = false; web.current?.reload() } return }
        }
        endAllActivities(); setActivityDevice(null); synced.current = null
        onSignedOut(); break
      case 'nativePush':
        if (session.mode === 'demo') return
        if (m.on) {
          const permission = await Notifications.requestPermissionsAsync()
          if (!permission.granted) { await Linking.openSettings(); return }
        }
        await setNativePushEnabled(m.on === true)
        await refreshReminders()
        break
      case 'key':
        if (session.mode !== 'demo' && m.key) { setRoutineConnection({ baseURL: url, key: m.key }); refreshRoutine() }
        if (!m.key || session.mode === 'demo') return // the demo's sample key never reaches the widgets, Watch or reminders
        if (synced.current === `${url} ${m.key}`) { await syncNativePush().catch(() => {}); return }
        synced.current = `${url} ${m.key}`
        try {
          setActivityDevice({ baseURL: url, key: m.key })
          if (session.mode === 'paired') await shareKey({ baseURL: url, key: m.key })
          await ensureWidgetKey(url, m.key)
          reloadWidgets()
          await requestPermission() // first time signed in: ask, then schedule
          await syncNativePush({ baseURL: url, key: m.key }).catch(() => {})
          await refreshReminders()
          await syncWatch({ baseURL: url, key: m.key })
          syncSpotlight(true)
        } catch (err) { synced.current = null; throw err } // try again on the next load
        break
    }
  }

  const bg = frame?.bg ?? theme ?? ui.c.bg
  const dark = frame ? frame.dark : theme ? isDark(theme) : ui.dark
  const bar = statusBarSurface(look, systemDark, bg)
  useEffect(() => { if (Platform.OS === 'android') KinwallNative?.navigationBar(dark) }, [dark])
  const view = failed ? (
    <View style={ui.root}><View style={ui.screen}>
      <Text style={ui.title}>Can't reach Kinwall</Text>
      <Text style={ui.muted}>{failed}</Text>
      <Pressable style={ui.button} onPress={() => { blankRestarts.current = 0; loadRecovery.retry() }}><Text style={ui.buttonText}>Try again</Text></Pressable>
      <Pressable onPress={onChangeServer}><Text style={ui.link}>Change server</Text></Pressable>
    </View></View>
  ) : startsPairing === null ? null : (
    <WebView
      ref={web}
      style={styles.web}
      key={mount.n}
      source={{ uri: mount.at ?? (startsPairing ? `${url}?start=pair` : url) }}
      applicationNameForUserAgent={`KinwallApp/${VERSION}`}
      injectedJavaScriptBeforeContentLoaded={bridge(origin, token, frame, session.mode !== 'demo' && nativePushAvailable(), statusBarHidden)}
      injectedJavaScriptBeforeContentLoadedForMainFrameOnly // the default, and required: the nonce is in here
      onMessage={onMessage}
      // Android sends a load start for a #/ route change, often with no end: only a real load counts.
      onLoadStart={(e) => { const was = pageUrl.current; track(e.nativeEvent.url); if (sameDocument(was, e.nativeEvent.url)) return; setLoading(true); clearTimeout(loadCheck.current); pageProbe.cancel() }}
      // Android can emit onLoad just before onError. Only a healthy page's
      // appearance/alive message resets retries, not native load events.
      onLoad={(e) => { pageUrl.current = e.nativeEvent.url; hideSplash(); setLoading(false); syncKey(); if (pending.current) { go(pending.current); pending.current = null }; clearTimeout(loadCheck.current); loadCheck.current = setTimeout(probe, 15_000) }}
      onNavigationStateChange={(s) => { canGoBack.current = s.canGoBack; track(s.url) }}
      onError={(e) => {
        pageUrl.current = null
        hideSplash()
        clearTimeout(loadCheck.current)
        pageProbe.cancel()
        setLoading(true)
        loadRecovery.failed(e.nativeEvent)
      }}
      renderError={() => <View style={ui.root}><View style={ui.screen}><Text style={ui.muted}>Connecting to Kinwall…</Text></View></View>}
      onContentProcessDidTerminate={(e) => restart(e.nativeEvent.url)} // iOS
      onRenderProcessGone={(e) => restart((e.nativeEvent as { url?: string }).url)} // Android: this web view can't be used again
      // Other schemes (tel:, mailto:) go straight to Linking without reaching the handler below;
      // intent: (the contact sheet's Video call, which Linking can't open) comes here for openOutside.
      originWhitelist={['http://*', 'https://*', 'intent:*']}
      // Other sites open outside the app (openOutside); Kinwall stays here.
      onShouldStartLoadWithRequest={(r) => {
        if (isKinwall(r.url) || r.url.startsWith('about:') || r.url.startsWith('blob:')) return true
        if (r.isTopFrame !== false) openOutside(r.url)
        return false
      }}
      onOpenWindow={(e) => { const u = e.nativeEvent.targetUrl; if (isKinwall(u)) web.current?.injectJavaScript(`location.href = ${JSON.stringify(u)}; true;`); else openOutside(u) }}
      onFileDownload={(e) => { Linking.openURL(e.nativeEvent.downloadUrl).catch(() => {}) }} // the photo zip, a saved drawing: the browser saves it
      contentInsetAdjustmentBehavior="never" // the page lays itself out with env(safe-area-inset-*)
      bounces={false}
      allowsInlineMediaPlayback
      allowsBackForwardNavigationGestures={false}
      allowsLinkPreview={false}
      setSupportMultipleWindows
      webviewDebuggingEnabled={__DEV__}
      domStorageEnabled
    />
  )

  const scanner = scanning && <Scanner facing={scanning} onDone={(code) => { setScanning(null); web.current?.injectJavaScript(barcodeScript(code)) }} />
  // Native owns the system-bar strip; the WebView still lays out clear of its safe-area inset.
  const statusBarBackground = !statusBarHidden && <View pointerEvents="none" style={{ position: 'absolute', top: 0, left: 0, right: 0, height: insets.top, backgroundColor: bar.color }} />

  // iOS: WebKit supplies the notch and status-bar insets; the page adapts to the chosen visibility.
  // Android: SafeAreaView follows system insets when visibility changes, including camera cutouts.
  return Platform.OS === 'ios' ? (
    <View style={[styles.root, { backgroundColor: bg }]}>
      <StatusBar hidden={statusBarHidden} style={bar.style} />
      {view}
      {statusBarBackground}
      {scanner}
    </View>
  ) : (
    <SafeAreaView style={[styles.root, { backgroundColor: bg }]}>
      <StatusBar hidden={statusBarHidden} style={bar.style} />
      {view}
      {statusBarBackground}
      {scanner}
    </SafeAreaView>
  )
}

function isDark(hex: string): boolean {
  const v = /^#([0-9a-f]{6})$/i.exec(hex)
  if (!v) return false
  const n = parseInt(v[1]!, 16)
  return (0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255)) / 255 < 0.5
}

const styles = StyleSheet.create({ root: { flex: 1 }, web: { flex: 1, backgroundColor: 'transparent' } })
