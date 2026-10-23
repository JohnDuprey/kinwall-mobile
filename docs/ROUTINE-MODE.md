# Routine mode development preview

This branch adds the iOS Screen Time bridge and a Device Activity monitor extension. The matching
`kinwall-routine-mode` worktree supplies **Chores → Free time**, the parent policy and the server
calculation. This is a prototype, not a shipped parental-control feature.

## Simulator

In the web worktree:

```sh
cd web
VITE_MOCK=1 npx vite --host 127.0.0.1 --port 5197 --strictPort
```

In this mobile worktree (Node 24):

```sh
npm ci
CI=1 npx expo prebuild --clean --platform ios
EXPO_PUBLIC_DEMO_URL=http://127.0.0.1:5197 EXPO_PUBLIC_ROUTINE_PREVIEW=1 npx expo start --localhost --port 8097
```

In a separate terminal, build using the desired simulator UUID (the dedicated test simulator is
named **Kinwall routine mode**):

```sh
xcodebuild -workspace ios/Kinwall.xcworkspace -scheme Kinwall -configuration Debug \
  -destination 'id=SIMULATOR_UUID' -derivedDataPath /tmp/kinwall-routine-derived \
  CODE_SIGNING_ALLOWED=NO RCT_METRO_PORT=8097 build
xcrun simctl install SIMULATOR_UUID /tmp/kinwall-routine-derived/Build/Products/Debug-iphonesimulator/Kinwall.app
xcrun simctl launch SIMULATOR_UUID family.kinwall.app
```

Do not force `-sdk iphonesimulator` globally: the app also embeds Watch targets that require the
Watch simulator SDK. The debug-only preview flag opens the fictional demo family's Free time
screen directly. Release builds ignore both preview environment variables.

In **Settings → Family → Routine mode**, Choose apps opens a native sheet with sample Games/Videos switches in the simulator. Completing
Maya's sample chores changes the preview from paused to available. Set a past cutoff and wait for Saved to
try bedtime; turn routine mode off to try the parent release. The simulator never claims to
shield actual installed apps. Demo state resets on reload.

## Physical devices

The existing app minimum remains iOS/iPadOS 17. Pair the child's device first, then open
**Chores → Free time → Approve Screen Time with a grown-up**. This requests `.child`
authorization on that child's device, using the child or teen Apple Account in Family Sharing.
It does not use individual self-control authorization.

On the parent's phone in the same Apple Family Sharing group, choose that child in
**Settings → Family → Routine mode** and tap **Choose apps for [child]**. The guardian picker
opens without requesting `.child` authorization on the parent's device and never applies
restrictions there. Apple may show apps from multiple authorized children; Kinwall sends the
saved opaque choices only to the selected child.

All-apps mode applies the server decision even before any picker choices exist: an empty
exception list is valid. Only enabled selected-app mode waits for app choices. Disabling
routine mode clears the native restrictions even if there is no saved selection.

Native code fetches and saves opaque Codable selections directly through `/api/routine-mode/:id/apps`.
The server encrypts them at rest and enforces parent-only writes and own-child reads. No opaque
selection reaches WebView or MCP. Optimistic revisions prevent one parent's old picker from
overwriting newer choices. Child devices import the choices, apply the server decision, and
report the applied revision through `/device`; Settings reads metadata only from `/devices`.
Parents cannot forge child acknowledgments. Reauthorization to a different child or server clears
the old local selection before binding the device again. Open Kinwall on the child device to
receive changes immediately; matching server and app builds also attempt background delivery.

Background refresh uses a cold-launch receiver and includes routine refresh in
the existing periodic background task. It recovers only the paired-device credential, never an
OAuth parent login or a shared widgets key. A notification carries only
`kinwall: { type: 'routine-sync', server: '<origin>' }`; the receiver checks that origin against
the existing connection and fetches current identity, app choices and policy through the same
authenticated flow used in the foreground. Notification fields cannot grant access or select a
different child. Sign-out invalidates an in-flight credential lookup, including a cold lookup
that has not connected yet. Background work never presents authorization or the app picker.

The receiver needs a matching server/gateway sender before silent notifications can wake it.
Silent hints also require that device's native push registration; periodic refresh does not
depend on notification permission.
Periodic refresh already provides another opportunity to receive changes, independently of
reminder permission or reminder-refresh failures, but iOS controls when that task runs. No
background path guarantees instant delivery, and opening Kinwall remains the manual fallback.

The app and `family.kinwall.app.routine-monitor` need the Family Controls entitlement, and both
use App Group `group.family.kinwall.routine`. Request Apple's distribution permission for the
extension as well as the app. No signing team or existing bundle identifier has changed.

Hardware decisions are fetched from the authenticated server; bridge payloads cannot grant
access. A local monitor is installed before an unlock and restores restrictions at the cutoff.
The one-day grant expiry uses UTC; recurring calendar callbacks use the saved household timezone,
so travelling with the device does not reinterpret the family's schedule.
Failed network requests retain the last policy; a failed monitor registration keeps apps blocked.
Only opaque Apple selection tokens and local enforcement state live in the shared App Group.

The app refreshes every 15 seconds while active and on foreground. Background remote unlock,
reboot/tamper behavior, authorization revocation, and real Family Sharing authorization require
physical-device testing. No physical device installation or production deployment is part of
this simulator prototype. Sign-out retains restrictions; a child cannot lift them by leaving Kinwall.

## School browser exceptions

The server policy includes `allowedWebsitesOnly` and `allowedWebDomains`. While locked, native code
uses `ManagedSettingsStore.webContent.blockedByFilter = .all(except: ...)`; when unlocked it
clears the routine store. The connected Kinwall server host is appended by the shell, so an
untrusted web bridge message cannot nominate an extra allowed host on hardware. The domains
are persisted with the selection so the monitor extension keeps school access at the cutoff.

The physical picker has **Pause** and **Keep available** selections. Only individual app tokens
are allowed in Keep available. Those tokens are subtracted from explicit blocked apps and passed
as exceptions to category shielding. Parents should select Safari/the school browser there.
When school-only website filtering is active, it replaces opaque website shielding to avoid a
second rule overriding school exceptions. Other Screen Time apps can still impose stricter rules.

The simulator picker adds a sample Safari exception, and status reports the preserved app count.
This previews configuration only. Test school SSO redirects, resource/CDN domains, browser
behavior and actual web filtering on a physical child device before treating this as enforced.

Website access is configured in Settings using **Allow all websites** or **Only allowed websites**.
The app picker accepts apps/categories to pause and individual apps to keep available, not website
blocks. Website links can be hidden individually without changing their permission.

Schedules are per child, with a daily start/end and optional weekday overrides. The native
client stores the validated weekly calendar separately from the last chore decision. The monitor
rechecks that calendar when its recurring daily, routine-window and nighttime intervals begin
or end, including first device use during those intervals. Apple invokes these callbacks while
the device is in use; they are not a general background polling timer.

Before the start, the local calendar allows access. At the start, a grant for yesterday cannot
unlock today's chores. An explicit empty required-chore list is schedule-only and repeats without
an old chore approval. Other days require a server-confirmed decision for that household date.
At the cutoff, the absolute grant expires. Per-day overrides use Sunday-first indices, matching
the server. Overnight routine windows remain unsupported.

The callback plan has fifteen stable activities plus the existing absolute grant-expiry activity.
Short routine/nighttime intervals expand to sixteen minutes to meet Apple's minimum, and every
callback recomputes the current policy rather than treating the callback itself as an unlock.
Unchanged calendars do not reinstall all activities on every foreground poll. A partial monitor
installation remains locked and retries on a future server check. The same Foundation-only
calendar code is compiled into the app and extension; its command-line regression test runs as
part of `npm test` on macOS. Actual callbacks, reboot behavior and shielding still require hardware QA.

The per-child `appMode` is `selected` (apps and/or categories) or `all`. All mode uses
`applicationCategories = .all(except: allowed.applicationTokens)`. Explicit individual app
allowances also override selected categories and individual apps. Apple exempts Kinwall from
all mode. Safari must be selected explicitly in **Keep available** on hardware; its token cannot
be generated from the bundle identifier. With the website allowlist on, the simulator preview
keeps its sample Safari available and explains this setup requirement. Simulator selection packets
are marked as previews and rejected by physical devices. Simulator choices are stored per child
in the preview session and never uploaded to a real family.
