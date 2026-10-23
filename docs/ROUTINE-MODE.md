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
Maya's sample chores changes the preview from paused to available. Set a past cutoff and save to
try bedtime; turn the agreement off to try the parent release. The simulator never claims to
shield actual installed apps. Demo state resets on reload.

## Physical devices

The existing app minimum remains iOS/iPadOS 17. The app requests `.child` authorization, not
revocable individual self-control authorization. Parent Kinwall access is verified against the
server before the native picker can open. Temporarily sign into Kinwall with parent access on the
child's device, open Settings → Family → Routine mode and select their apps, then sign out and pair to that child. A previously configured
selection is bound to its child; another child's pairing cannot reuse it.

The app and `family.kinwall.app.routine-monitor` need the Family Controls entitlement, and both
use App Group `group.family.kinwall.routine`. Request Apple's distribution permission for the
extension as well as the app. No signing team or existing bundle identifier has changed.

Hardware decisions are fetched from the authenticated server; bridge payloads cannot grant
access. A local monitor is installed before an unlock and restores restrictions at the cutoff.
Its timestamps use UTC so the device's timezone does not reinterpret the household cutoff.
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

Schedules are per child, with a daily start/end and optional weekday overrides. Before the start,
the server grants access only until that start boundary. The existing local monitor closes the
grant there; opening Kinwall refreshes whether chores have earned free time. Overnight windows
are not supported. Background schedule refresh still needs physical-device work.

The per-child `appMode` is `selected` (apps and/or categories) or `all`. All mode uses
`applicationCategories = .all(except: allowed.applicationTokens)`. Explicit individual app
allowances also override selected categories and individual apps. Apple exempts Kinwall from
all mode. Safari must be selected explicitly in **Keep available** on hardware; its token cannot
be generated from the bundle identifier. With the website allowlist on, the simulator preview
keeps its sample Safari available and explains this setup requirement. App-token syncing between
parent and child devices remains unimplemented.
