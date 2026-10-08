# Kinwall mobile (iPhone, iPad, Apple Watch and Android): project plan

Open source, not released yet. Nothing here ships to the App Store until there's a paid Apple Developer Program membership; until then the apps run in the Simulator and, signed with a free Apple ID, on our own devices.

**Not enrolled yet.** Builds use a free Apple ID and expire after 7 days. TestFlight (`scripts/testflight.sh`) comes with the paid membership.

**Update 2026-09-27: React Native (Expo), and Android.** The phone and tablet app is now one Expo app for iOS and Android (`src/`), replacing the SwiftUI frame. It does what the Swift frame did: the address screen, OAuth in the system's auth sheet (`expo-web-browser`) or pairing, the web view with the same in-app flags, widget links (`family.kinwall.app:/open?to=…`), local reminders and background refresh, the theme-colored status bar. The iOS widgets, the Watch app, complications and Siri stay Swift on `KinwallKit`, added to the generated Xcode project by `@bacons/apple-targets` and `plugins/withKinwallNative.js`, and still read the widgets' key from the shared Keychain group `family.kinwall.shared`. XcodeGen and `project.yml` are gone. Android gets the same shell, a notification channel for reminders, the back button stepping back through the web app, and a home-screen widget (now and next, chores left). **Wear OS comes later** (M8).

## Goal

Native apps for the family who already use Kinwall. On iPhone and iPad the app shows **Kinwall's own web app** in a native frame, so every screen and feature is there from day one and there's one UI to maintain. Native code does what a web page can't: widgets and complications, the Apple Watch app, Siri and Shortcuts, and (with a paid membership) push notifications.

## What we can and can't do without a paid membership

| | Free Apple ID ("Personal Team") | Paid membership |
|---|---|---|
| Simulator (iPhone, iPad, Watch) | Yes, unlimited | Yes |
| Run on our own iPhone, iPad and paired Watch | Yes, from Xcode. The signature expires after **7 days**; reinstall from Xcode to renew | Yes, a year |
| Widgets and watch complications (WidgetKit) | Yes | Yes |
| Siri and Shortcuts (App Intents) | Yes | Yes |
| Share extension (sends a shared link, place, photo or text to Kinwall, imports a contact; shared Keychain group, no App Group) | Yes | Yes |
| **App Groups** (app and widget share storage) | No | Yes |
| **Push notifications** (APNs), including Live Activity push-to-start | No | Yes |
| **Time Sensitive notifications** (leave-by and medicine reminders break through a Focus) | No: the Personal Team's profile doesn't carry the entitlement, so it's off unless prebuilt with `KINWALL_TIME_SENSITIVE=1` or `KINWALL_PUSH=1` | Yes |
| Reminder buttons (Snooze, Taken, Done), the Focus filter, Smart Stack relevance, small Live Activities for the Watch and CarPlay | Yes | Yes |
| Live Activities started by the app (cooking timer, shopping trip, leave-by while open) | Yes | Yes |
| iCloud, Sign in with Apple, Associated Domains (passkeys, universal links) | No | Yes |
| TestFlight, App Store | No | Yes |

**Design consequences:**

- **Signing in:** the app uses Kinwall's existing TV-style pairing. It shows a 6-digit code, and an admin approves it under **Settings → Access → Displays**. The app gets its own display key, stored in the Keychain. No passkeys yet, since they need Associated Domains.
- **Widgets:** each widget fetches its own data with the same key. Sharing the key between the app and its widget needs a shared Keychain access group. Whether a Personal Team allows that is **to be verified in M3**. If it doesn't, the widget pairs separately.
- **Freshness:** without push, the apps poll `GET /api/rev` (as the web app does, every 30 s while open) and use background app refresh and WidgetKit timelines. Real-time push waits for the paid membership (M6).

## Signing in, and why not passkeys

Passkeys are tied to a website's domain. Inside an app's web view they only work for domains the app declares ahead of time through Associated Domains. That needs the paid membership, and even then it can only cover domains we know in advance, like `*.kinwall.family`. A self-hosted server on its own domain can never be listed. So:

- **Sign in (built):** the app opens the server's OAuth consent screen in a Safari sheet (`ASWebAuthenticationSession`). That's Safari's own context, so a passkey works on any domain, self-hosted included. The admin picks full or everyday access, and the app receives a code on its `family.kinwall.app:/oauth` link and swaps it for keys. Access keys last an hour and the app refreshes them ahead of time; refresh tokens last 90 days and rotate. The app shows under Settings → Access → Connected apps, and **Sign out** revokes it. No paid membership needed.
- **Connecting Google or Microsoft (built 2026-10-02, needs the matching kinwall server):** **Connect Google** / **Connect Outlook** (and Google Photos) start in the web view, which gets the sign-in's cookie, and the provider's page opens in the in-app browser, which has its own cookies. The server's callback there offers **Open in the Kinwall app**, a `family.kinwall.app:/provider-return?kind=…&state=…&code=…` link (a path apart from `/oauth`, since Android's auth session matches by prefix). The app checks it (`src/providerReturn.ts`: kind `google` or `microsoft`, a plain state and code of bounded length), closes the in-app browser on iOS, and loads `<its own server>/api/oauth/<kind>/callback?code&state` in the web view, where the cookie is. The host never comes from the link. Signed out or in the demo the link is dropped. The page sees `window.kinwallNative.providerReturn` and asks older apps to update first. Checked with unit tests; not yet on a device.
- **Pair with a code (built, the fallback):** for a child's phone or a wall iPad. The app shows a code and an admin approves it.
- **Admin steps that ask for the passkey again** (calendar accounts, API keys, webhooks) still happen in Safari: the web view itself can't use passkeys.
- **Hosted, with the paid membership:** Associated Domains for `*.kinwall.family` could also make passkeys work directly in the app's web view.

## No passkey yet (built)

| Situation | What happens |
|---|---|
| **Brand-new server,** not set up yet | The consent link runs the setup wizard in the same Safari sheet, where creating a passkey works, then continues to approval |
| **Set up, but no passkey here** | **Use a recovery code** on the consent screen. After that, **Create a passkey** is offered before **Allow** |
| **Not an admin** (a child) | **Pair with a code**, or an admin approves in the sheet on the child's phone |

## Architecture

- **KinwallKit** (Swift package, done in M0) holds the API client, models, pairing, Keychain storage and household dates. It has no UI and is tested on macOS with `swift test`, including a live test against a local Kinwall server.
- **Kinwall** is one Expo (React Native) app for iPhone, iPad (iOS 17+) and Android: a native frame around the household's own Kinwall web app, full screen. It opens on the web app's pairing screen; once paired, the frame copies the key into the Keychain for the widgets, Watch and Siri, so there's one pairing. The web app gets a flag telling it it's inside the app (`window.kinwallNative`, a `KinwallApp/` user agent, and `<html data-native>`). Inside the app it hides the Add to Home Screen card, explains that push needs Safari for now, offers **Pair this app** instead of passkey sign-in, and drops the gap it keeps under the status bar, which the app hides.
- **Kinwall Watch** is a watchOS 10+ app that talks to the server directly over Wi-Fi or the iPhone's connection. It's paired by handing over the phone's connection with WatchConnectivity, so there's no code to type on a watch.
- **Kinwall Widgets** is a WidgetKit extension for the Home Screen, Lock Screen, StandBy and watch complications.
- **The projects** are generated by `npx expo prebuild` from `app.json`, the config plugins and `targets/*/expo-target.config.js`, so neither `.pbxproj` nor Gradle files are committed.
- **The native parts** (widgets, Watch, Siri) use KinwallKit and keep a small cache so they show the last known state offline. Their look follows the household's color scheme from `/api/settings`.

## Milestones

### M0: Foundation (done)
- [x] Private repo, plan, KinwallKit with the client, models, pairing, Keychain store and household dates
- [x] Unit tests and a live pairing, chores and lists test against a real server (7/7 passing)
- [x] The iOS app, watch app and widget targets (first with XcodeGen, now generated by Expo prebuild)
- [x] Build every target for the Simulator

### M1: The iPhone and iPad app (web UI in a native frame)
- A web view frame ([`react-native-webview`](https://github.com/react-native-webview/react-native-webview)), full screen, loading the household's Kinwall URL. The first run asks for the address: hosted `*.kinwall.family` or a self-hosted URL.
- Pairing happens in the web app's own pairing screen. Once paired, the frame reads the key and saves it to the Keychain for the native parts.
- The status bar and background follow the page's `theme-color`, and the safe areas match the installed web app.
- **No flash at launch.** The page reports its look (mode, dark or light, and the background and card colors for both), and the app saves it (`src/appearance.ts`). The next launch keeps the launch screen up until the saved session is known and the page has loaded, paints the frame in the saved colors (following the system in auto), and puts them on the page before its first frame. OAuth keys that lapsed while the app was closed are refreshed before the page opens, and a key the page rejects shows a blank screen while the app takes over (it refreshes the key even if it looks current, and shows "Can't reach Kinwall" rather than reloading forever), never the pairing screen; the page itself offers Retry if the app hasn't taken over within 10 seconds. Sign-out goes back to the app's own colors; the demo's are never saved. The launch screen itself is a fixed image Apple caches, so it can only follow the system's light or dark mode in Kinwall's default colors.
- **Never stuck blank.** iOS ends a background web view's process to free memory (Android's renderer can go too), which leaves the page blank on return. The app starts a fresh web view where the page was when that happens, and also asks the page on every return and 15 seconds after each load: no answer, or a page that drew nothing (a script that failed to load at launch), gets a fresh web view, twice at most, then the "Can't reach Kinwall" screen. The web app reloads once by itself if its own script fails to load or it crashes, then offers Reload.
- **Only the server's own pages are trusted** (`src/bridge.ts`, since 2026-09-30). A page stays in the app, and gets the sign-in key, only when its origin (scheme, host and port) is exactly the server's: an `http://` page on the same host opens outside and never gets the key. Messages from the page reach the native side only with a random nonce made at each launch, which lives in the bridge script injected into the main frame alone; messages from other frames (an activity plugin's, on Android) or from a `/plugins/` page are dropped. The nonce is added by the app's own shim of `webkit.messageHandlers.kinwall`, so the web app needs no change and older servers keep working.
- Links to other sites open in Safari. Photo uploads and the file picker work, and so do downloads (the photo zip).
- **Web app changes** (in the `kinwall` repo): detect the frame (a user-agent suffix, or a flag the frame sets), then hide the Add to Home Screen card, the web push settings and **Clear cache and reload**.
- **Notifications:** the frame can't receive web push, since Apple only allows it for Home Screen web apps. Until M6, the Notifications card says so and points to the bell feed.

### M2: iPad wall mode
- Keep the screen awake while the app is open, plus a Guided Access how-to for a kiosk-style wall. Everything else already lives in the web app: the Board, the idle reset, quiet hours and the screensaver.

The feature menu for M3 to M5 is in [WIDGETS-AND-WATCH.md](WIDGETS-AND-WATCH.md).

### M3: Widgets
- Now/Next (small and medium), today's chores left (with interactive tick-off via App Intents), a list (for example Groceries), Lock Screen and StandBy variants
- Verify whether shared Keychain access works on a Personal Team; if not, a widget pairing flow

### M4: Apple Watch
- Hand the connection over from the iPhone (WatchConnectivity)
- My chores (tick, with "Who did it?" via the watch's family picker), Groceries (tick, add by dictation), Now/Next
- Complications: next event, chores left

### M5: Siri and Shortcuts
- "Add milk to Groceries", "What's next?", "Mark Take out trash done", "How many points does Maya have?"
- Spotlight for lists and chores

### M6: When there's a paid membership (not enrolled yet)
- **Live Activities while the app is closed** (built behind configuration, off until then): see [Turning on Live Activity push](#turning-on-live-activity-push)
- **APNs push:** the server gains an APNs sender beside web push, using the same notification preferences
- **Time Sensitive reminders:** prebuild with `KINWALL_PUSH=1` (or `KINWALL_TIME_SENSITIVE=1`), which adds the entitlement; leave-by and medicine reminders then break through a Focus (docs/WIDGETS-AND-WATCH.md, Reminders with buttons)
- **App Groups** for the app and widgets (retire any workaround from M3)
- **Passkeys and universal links** (Associated Domains on `kinwall.family`)
- TestFlight for the family, then an App Store listing: privacy manifest, screenshots, review notes (demo server)

### M7: Android (in progress)
- [x] The shared Expo shell: address screen, OAuth or pairing, web view, deep links, reminders on their own notification channel, the back button through web history
- [x] A home-screen widget (now and next, chores left) rendered from JavaScript with [`react-native-android-widget`](https://github.com/sAleksovski/react-native-android-widget)
- [x] Build and run on an emulator (Pixel, Android 16): the countdowns below. A phone is still to try
- [x] Parity with the iPhone app's own touches (2026-09-29): **Try the demo** (sample reminders, and the widget shows a sample family while the demo is open), the saved family colors with no flash (the launch screen in Kinwall's light or dark color, the frame and page in the family's; the navigation bar's buttons now follow the page too), the keyboard (the first screen keeps **Try the demo** above it; in the web view the content makes room for it, since edge to edge on Android 15 and later the window no longer shrinks), the key refresh before the page opens, keep-awake while shopping, recipe links from the share sheet, `family.kinwall.app:/open` links, the back button through the web history, and safe areas edge to edge. The Settings line about countdowns needs the web change under [Android countdowns](#android-countdowns-built-2026-09-29)
- [x] The Live Activities as ongoing notifications, and leave-by countdowns scheduled with no push: see [Android countdowns](#android-countdowns-built-2026-09-29)
- [x] On-time alarms (`USE_EXACT_ALARM`, with `SCHEDULE_EXACT_ALARM` capped at Android 12L) and no `SYSTEM_ALERT_WINDOW` in release builds (2026-09-30); Play needs the exact-alarm declaration (PUBLISHING.md)
- [x] A notification channel per purpose, and Snooze, Open, Taken and Done on reminders without opening the app, with the iPhone's medicine reminders and chore nudge (2026-09-30): see [WIDGETS-AND-WATCH.md](WIDGETS-AND-WATCH.md#android)
- [x] Widgets v2: the family's colors and dark mode, plus Chores, List and Take now (2026-09-30)
- [x] Launcher shortcuts and Quick Settings tiles (2026-09-30)
- [ ] Try all of the above on a phone with a real family (the list at the end of WIDGETS-AND-WATCH.md, Android)
- [ ] Play Console listing and internal testing track (meanwhile each GitHub Release has an installable APK, and EAS `preview` gives one too)
- [ ] The web app marks itself `data-native="ios"` inside either app; give Android its own value if styles need to differ

### Releases
- [x] release-please: a `chore: release x.y.z` PR from the Conventional Commits on `main`; merging it tags `vX.Y.Z` and makes the GitHub Release (versions independent of the server's)
- [x] Unsigned builds attached to each release (`.github/workflows/build.yml`): an Android APK signed with a throwaway key, the unsigned APK, an unsigned IPA with the widgets, share extension and Watch app, a Simulator build, and `SHA256SUMS.txt` (README, Install a test build)
- [x] Build numbers from the version, `major*10000 + minor*100 + patch`, through `KINWALL_BUILD_NUMBER` and `app.config.js`
- [ ] First run on GitHub (needs "Allow GitHub Actions to create and approve pull requests" in the repo settings)
- [ ] A kept signing key (a repo secret) so Android test builds update in place, if that becomes worth it; signed store builds come with M6 and the Play Console

### M8: Wear OS (later)
- A watch app like the Apple Watch one: Now/Next, my chores, Groceries, and tiles and complications. Native Kotlin (Compose for Wear OS), with the key handed over from the phone app over the Wearable Data Layer.

### M9: Apple Health (later, stretch)

Opt-in, off by default: a family setting ("Let the app sync with Apple Health", like the AI
health-access switch) plus iOS's own per-type Health permission sheet on each device. Only the
device owner's data: Health is per iPhone owner, so a shared wall or a parent's phone never
writes a kid's data into the parent's Health; a kid's own iPhone can sync the kid's.

1. Read sleep duration (from a watch or other source) to pre-fill the morning check-in ("You slept
   6 h 10 min. How did it feel?") and give the Energy battery real hours alongside the rating.
2. Write Temp check feelings as State of Mind entries (iOS 17+; valence plus labels such as happy,
   tired, stressed).
3. Write Health tracker measurements (height, weight, temperature) as Health quantities.
4. Maybe: steps or exercise minutes as battery drain on physically heavy days.

Not a fit: sleep quality ratings (Health stores only times and stages), vaccines and visit records
(clinical records are read-only for apps), medications (verify what apps can read or write before
promising anything). App Review: privacy policy covering Health, no ads or third-party sharing,
purpose-limited use; confirm the free team can use HealthKit before building.

## Live Activities (built 2026-09-29)

Three Live Activities: a cooking timer, a shopping trip (with **Got it** and **Open**) and the next leave-by or start-prep time. See [WIDGETS-AND-WATCH.md](WIDGETS-AND-WATCH.md#live-activities). Everything the app starts itself works on a free Personal Team: ActivityKit and interactive App Intents need no capability, and **Got it** ticks the item with the widgets' key from the shared Keychain group, so it needs no App Group. The deployment target is iOS 17, so the < 16.1 and < 17 cases can't occur; push-to-start is checked for iOS 17.2.

What waits for the paid membership is Apple push: starting the leave-by activity while the app is closed, and ending it on time. The code is in place and off:

- **App:** `KINWALL_PUSH=1` at prebuild keeps the `aps-environment` entitlement (otherwise removed, since a Personal Team can't sign it) and sets `KinwallPush` in Info.plist. Only then does the app ask for its push-to-start token and each leave-by activity's update token, and send them to the server (`PUT /api/live-activities/tokens` with the page's key; never in the demo, and the push-to-start token only while the phone's person has transition reminders on and notifications are allowed).
- **Server:** does nothing until `APNS_*` is set (kinwall `docs/self-hosting/configuration.md`).

### Turning on Live Activity push

1. Enroll, and in **Certificates, Identifiers & Profiles** give the App ID `family.kinwall.app` the **Push Notifications** capability.
2. Under **Keys**, create a key with **Apple Push Notifications service (APNs)**. Download the `.p8` (once), and note its Key ID and the Team ID.
3. Build with `KINWALL_PUSH=1 CI=1 npx expo prebuild --clean`, signed with the paid team. For TestFlight and the App Store, `aps-environment` must be `production` (expo-notifications writes `development`; set it in `withLocalOnly` for release builds).
4. On the Kinwall server: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY` (the `.p8` contents, a secret), `APNS_BUNDLE_ID=family.kinwall.app`, and `APNS_SANDBOX=1` while testing builds installed from Xcode.
5. Hosted (Cloudflare Workers): nothing extra. A deployed Worker reaches APNs with a plain `fetch` (Cloudflare's edge speaks HTTP/2 to Apple); local `wrangler dev` on macOS can't, so test on a deployed Worker. Docker and Node use Node's HTTP/2 client. `APNS_SEND` (a relay) is only an optional override.
7. Self-hosted servers: only the publisher's key can sign pushes for the official Kinwall app, so a self-hosted server can't push to it with its own key. Plan (not built): a push gateway at push.kinwall.family, itself a Worker, that relays Live Activity pushes for self-hosted servers. Until then, on self-hosted, the app starts leave-by activities only while it's open.
6. Check: give a person transition reminders, set their phone's owner to them (Settings → Access), allow notifications, close the app, and add an event with travel time 35 minutes out. The Live Activity should appear at the first reminder and go away when the event starts.

## Android countdowns (built 2026-09-29)

The Live Activities' Android counterpart, with no Firebase and no push. `modules/kinwall-native/android` makes the local Expo module work on Android too (it was iOS only):

- **Ongoing notifications** (`Countdowns.kt`), one of each kind at a time: cooking and shopping on **Timers and countdowns**, leave-by on **Leave-by** and medicine on **Medicine** (since 2026-09-30; see [WIDGETS-AND-WATCH.md](WIDGETS-AND-WATCH.md#android)), each kind in a notification group of its own. The web app's `activity` and `activityEnd` messages reach them the same way as on iPhone (`src/WebShell.tsx`, `src/liveActivities.ts`: the bridge shims `webkit.messageHandlers.kinwall` onto the WebView's `postMessage`, so `web/src/native.ts` needs no change), with the same payloads and the words of `targets/widgets/LiveActivities.swift`. Countdowns are a chronometer counting down to `when`, so they tick without updates; `setOnlyAlertOnce` keeps updates quiet.
  - **Cooking:** the soonest timer. At its end an alarm switches it to "Done: Rice", no longer ongoing, which goes after 30 minutes. **Open** opens the app. Every running timer also rings (built 2026-09-30): the payload's `alarms` each get an exact alarm that posts "Time's up: Rice" on its own high-importance channel, **Cooking timers**, with the alarm sound (`USAGE_ALARM`) and vibration, over and over until **Stop**, a tap (opens the app), a swipe, or ten minutes. Each payload replaces the last set, so pause, reset and cancel on the page take a timer away and resume sets it again. Not while cooking mode is on screen (the app in front, the screen on and unlocked), since the page beeps; closing cooking mode and sign-out cancel them and stop one that's ringing. No hand-off to the Clock app. It rings on time with the exact-alarm permission, as below. Pages from before `alarms` keep the old single ring of the countdown.
  - **Shopping:** the next item in walking order and how many are left. **Got it** ticks the item from a `BroadcastReceiver` with the widgets' key (`PATCH api/lists/<id>/items/<item>`, with the entry's own `listId` when a combined trip carries the other list's item), then moves on to the next one the page sent, without opening the app (the demo's list just moves on; signed out or offline, nothing changes). **Open** opens `lists/<id>/shop`. The trip's size is the most items left seen, for the progress bar.
  - **Leave-by / prep-by:** counts down to the time, then says the page's "now" line (or "Time to leave") until the event starts (`setTimeoutAfter`). **Open** opens the calendar.
  - **Medicine** (`medication`): 💊 and the web app's headline ("Time for…", "Still time for…"; generic unless the device opted into names, which the web reads from its web-push subscription, so in the app it stays generic), "Due now · still time until 8:00 PM" or, once late, "Still time · until 8:00 PM", counting down to the end of the window, where it goes. Never "missed". **Taken** and **Snooze 10 min** mark the dose from a `BroadcastReceiver` with the widgets' key, which belongs to the device's person (`POST api/medications/<id>/doses`): Taken ends it, Snooze says "Snoozed · back at 7:40 PM" and comes back by itself. Skipped on the page ends it too (the web's end message).
  - **Android 16 (API 36):** they ask to be promoted to Live Updates (`setRequestPromotedOngoing`, `POST_PROMOTED_NOTIFICATIONS`, a short chip text), and the trip uses `ProgressStyle` (done of total). Older versions get a plain ongoing notification with a progress bar. Not colorized (Live Updates can't be); the family's accent tints the icon.
  - **Ending:** the web's end message, a timer 30 minutes after it rang, Done shopping (the page ends the trip; all done also stops being ongoing), the event's start, and sign-out (everything, and the alarms). Each kind's last payload is kept, so alarms, Got it and a restart can redraw it without the app.
- **Leave-by scheduled locally** (`src/leaveBy.ts`, tested): on every sync (app opens, returns, signs in) and every background refresh, the app works out this device's person's leave-by and prep-by times for the next 24 hours from the event list it already fetches for reminders, with the web app's rules (their events or everyone's, prep for the meal's cook, leave-by only when turned on, from the first transition warning until the start). The person is the device's owner from `GET /api/me` with the page's key, kept for background runs. `Countdowns.kt` sets an exact alarm (`setExactAndAllowWhileIdle`) at each first warning that posts the countdown even with the app closed, and re-arms them after a restart or an update (`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`). Since 2026-09-30 the app declares `USE_EXACT_ALARM`, which Android 13 and later grant at install (and `SCHEDULE_EXACT_ALARM` for 12 and 12L, granted by default there), so they're on time. Should neither be granted (a Play build without the declaration), it falls back to `setAndAllowWhileIdle`: the countdown still comes, up to several minutes late when the phone is idle. The words are generic ("Leave by 4:40 PM") until the page is open, which sends its own.
- **Background refresh:** the existing reminders task (expo-background-task, which is WorkManager on Android) runs every 15 minutes on Android instead of every 4 hours, and stops at the missing key when signed out.
- **Keys:** `keychainGet`/`keychainSet` on Android keep values AES-GCM encrypted under an Android Keystore key (`Keychain.kt`), so Got it can read the widgets' key with the app closed. An Android install that had the widgets' key in expo-secure-store mints a new one on its next sign-in; OAuth tokens move over by themselves (`src/oauth.ts`).
- **Lock Screen privacy:** `VISIBILITY_PRIVATE` with a public version that says only "Kitchen timer", "Shopping trip", "Time to leave soon" or "Medicine reminder", which Android shows when the phone hides sensitive notification content on the Lock Screen. iOS has no rule of its own here (the web app keeps medicine names and other health details out of these payloads), so the device's setting decides on both.
- **Settings line:** `window.kinwallNative.liveActivities` is true on Android when notifications and the channel are on, and `platform` is `"android"`.

Checked on the Pixel emulator (Android 16, API 36.0) with the demo: the leave-by countdown appears and ticks, the shopping trip shows its progress, **Got it** moves it to the next item with the app in the background, and Done shopping ends it. The notification asks for promotion (`android.requestPromotedOngoing`), but this image (API 36.0) doesn't promote it: the status bar chip is still to check on a newer Android 16 image or a phone. Android bundles the countdowns with the reminders once there are four or more of the app's notifications.

**Web changes needed** (kinwall, not made here): `liveActivitiesLine` in `web/src/native.ts` should take the platform (`window.kinwallNative.platform`) and on Android say "Countdowns show as ongoing notifications. Turn them off in Android Settings → Apps → Kinwall → Notifications." (and when off: "Countdowns as ongoing notifications: Off. Turn them on in Android Settings → Apps → Kinwall → Notifications."). Until then the Android app shows the iPhone wording. `appLiveActivities`' comment ("null outside the iPhone app") changes with it.

Also for the web app (2026-09-30), both optional and Android only:
- **Let medicine through Do Not Disturb:** where the Notifications section talks about medicine reminders, when `window.kinwallNative.notificationSettings` is true, a link that posts `{ type: 'notificationSettings', channel: 'medicine' }`; the app opens the Medicine channel's page in Android Settings, where **Override Do Not Disturb** is. Any channel id works (`reminders`, `leave_by`, `medicine`, `chores`, `countdowns`, `cooking_timers`), so the chore nudge can get a "Turn on the chore nudge" link to `chores` the same way.
- **Add a Quick Settings tile:** when `window.kinwallNative.quickSettingsTiles` is true (Android 13 and later), a button that posts `{ type: 'addTile', tile: 'groceries' }` (or `'night'`, e.g. next to the night screen); Android asks the person itself.

## Server work (in the `kinwall` repo)

None is needed for M0 to M5; everything above uses existing endpoints. Nice-to-haves, as they come up:

- **Pairing:** a `kind: "ios" | "watchos"` hint on `/api/pair`, so Settings → Access → Displays can show "iPhone app" instead of a generic display.
- **Checklist and snapshot endpoints** are already there; the Board has `GET /api/board`.
- **M6:** APNs delivery in `notify.ts`, plus device tokens stored like web push subscriptions.

## Action items

**Claude:**

1. **Done:** repo, plan, KinwallKit and tests; M1 to M5 in Swift; the move to Expo with the native targets kept.
2. M7: build and test Android once a machine has JDK 17 and the Android SDK.
3. M8: Wear OS.

**You:**

1. **For Android:** a machine with JDK 17 and the Android SDK (Android Studio), or an Expo account for EAS builds.
2. **To run on your own iPhone, iPad or Watch:**
   - In Xcode, go to **Settings → Accounts** and sign in with your Apple ID. This creates the free Personal Team.
   - Turn on **Developer Mode** on each device: **Settings → Privacy & Security → Developer Mode**.
   - Expect to reinstall from Xcode every 7 days.
3. **Before M1 ships to the family's phones:** decide whether the apps pair with your hosted household, a local server, or both. The app supports any URL either way.
4. **Later:** the Apple Developer Program ($99/year) unlocks M6.

## App Store readiness (before the first submission)

- [x] **More than a website (4.2).** Built 2026-09-29 and checked in the Simulator: interactive widgets (Chores, List, Take now, Daily check-in), Lock Screen widgets (Next event, Chores left, Take now, Energy gauge), a StandBy clock, Controls (Add to Groceries, Start shopping, Night screen), Siri and Shortcuts (six App Shortcuts with list, person, chore and store entities), Spotlight (recipes, lists, contacts), Live Activities, the share sheet's recipe import, and the Watch app (Today, My chores, Check-in, Take now, Lists, complications, transition taps). The screenshots and review notes lead with these. The app handles no network gracefully (the "Can't reach Kinwall" screen, never a blank page), shows no browser chrome, and opens other sites in the in-app browser.
- [ ] **No purchases in the app (3.1.1).** No prices, plans, sign-up or "subscribe" anywhere in the app: it only signs in to an existing Kinwall, hosted or self-hosted. Checked 2026-09-28: the app has none. Decided 2026-09-28: payment is web-only and never goes through the App Store, so the app stays sign-in only (no prices, plans, sign-up or purchase links). Under 3.1.1, adding any of those to the app would require in-app purchase.
- [ ] **Reviewer access.** **Try the demo** on the first screen opens the demo family with no sign-in, and shows the native parts with built-in sample data: the widgets show the demo family and two sample reminders arrive within a minute (README). The review notes say so, point to the widgets (Home Screen → Edit → Add Widget → Kinwall), and also give a hosted test family with a pairing code in case they want to try sign-in.
- [x] **Account deletion (5.1.1(v)).** Accounts are created on the family's server, not in the app. Two paths: the web app's **Settings → Access → Your data → Manage or delete this family** (hosted; the host's `HOST_PORTAL_URL`), and iPhone **Settings → Kinwall → Deleting your family's account** (`native/ios/Settings.bundle`), which says how for hosted and for a family's own server. Still wanted in the web app: the same instructions in Your data when there's no host page (self-hosted), so the path is inside the app for everyone.
- [ ] **Privacy.** Privacy policy URL; privacy nutrition labels that match what the app and server collect (the Health tracker is health data, encrypted at rest); no third-party analytics. **Done:** the privacy manifests for the app and every extension, with required-reason APIs ([PRIVACY-MANIFEST.md](PRIVACY-MANIFEST.md), whose data list is what the nutrition labels should say).
- [ ] **Third-party AI (5.1.2).** The privacy policy says connected apps (Claude and others over MCP) get family data only when a parent connects them, never health entries unless turned on.
- [ ] **Kids.** Not in the Kids category; age rating 4+; no purchase or outside links shown on a kid's device.
- [ ] **Sign in with Apple (4.8)** only if a third-party account login (for example "Sign in with Google") is ever added. Calendar sync with Google doesn't count.
- [ ] **Only documented APIs.** The share extension imports inside the sheet (no opening the app through the responder chain).
- [ ] **Screenshots.** Generated from the demo in the Simulator (2026-09-29): 6.9" iPhone (1320 × 2868), 6.5" iPhone (1284 × 2778), 13" iPad (2064 × 2752) and Apple Watch (416 × 496), kept outside the repo. Retake them before submitting if the web app's look changes.
- [ ] **Apple Developer Program** membership (M6). A Personal Team can't submit.
- [ ] **Live Activities and push.** Push-based Live Activities aren't needed for review: the cooking timer, shopping trip and open-app leave-by work without them. Only builds that use Apple push get the entitlement (`KINWALL_PUSH=1` at prebuild), and the listing, screenshots and review notes don't promise closed-app countdowns until push is live.

## Risks

- **7-day expiry** on a Personal Team makes daily use by the family awkward. Treat M1 to M5 as a preview until M6.
- **No push until M6:** on iPhone, the installed web app gets notifications and the native app doesn't. Until then the native app's reasons to exist are widgets, the Watch and Siri.
- **App Store review (M6):** Apple rejects apps that only frame a website (guideline 4.2). Widgets, the Watch app, Siri and push are what make this more than that, so they ship before a submission.
- **Widget and app key sharing** may not work on a Personal Team (see M3).
- **Polling costs battery** if overdone. Poll `rev` only while the app is in the foreground, and rely on timelines otherwise.
- **API drift:** KinwallKit decodes only the fields it uses. The live test catches renamed or reshaped fields, which is how M0 caught `GET /api/lists/{id}` wrapping the list in `list`.
