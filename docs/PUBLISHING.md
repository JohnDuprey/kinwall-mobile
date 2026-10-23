# Publishing to the App Store and Google Play

How a release of the Kinwall app gets into the stores. The unsigned test builds on GitHub Releases
are separate (see the README); store builds are signed with the publisher's accounts.

Identifiers: iOS bundle ID and Android package are both `family.kinwall.app`.

Before merging the release-please PR, run the TypeScript and JavaScript checks, `swift test
--package-path KinwallKit`, and a clean Expo prebuild. The Checks workflow runs these on pushes
and pull requests (prebuild uses `--no-install`; full native builds run in App builds). Review
the generated version changes together: the manifest, app config, package and lockfile must agree.
Store uploads also depend on account access; a successful app build alone does not confirm it.

## Apple App Store (iPhone, iPad, Apple Watch)

**Once**

1. Apple Developer Program membership (the individual enrollment).
2. In App Store Connect, create the app with bundle ID `family.kinwall.app` (register the App IDs for
   the widgets, share extension and Watch app too; Xcode or EAS can do this).
3. Fill in the app record: name, subtitle, description, keywords, support and privacy policy URLs,
   category (Productivity or Lifestyle), age rating questionnaire (4+ expected), and the App
   Privacy "nutrition label" (match `docs/PRIVACY-MANIFEST.md`: family data sent to the family's own
   server, linked to the user, not used for tracking).
4. Export compliance: the app only uses standard HTTPS, so it's exempt; set
   `ITSAppUsesNonExemptEncryption` to `false` in the iOS config so each build doesn't ask.
5. Signing: let EAS manage certificates and profiles (`eas credentials`), or Xcode's automatic
   signing with the paid team.

The Watch target must declare `icon` in `targets/watch/expo-target.config.js`. An
`AppIcon.appiconset` on its own is not enough: apple-targets uses that declaration to set
`ASSETCATALOG_COMPILER_APPICON_NAME`, and the asset compiler generates the icon metadata
(`CFBundleIconName` and `CFBundleIcons`) required by App Store Connect.

App Intent descriptions must not contain the reserved name "Apple" (App Store validation
error ITMS-90626). Describe the behavior in plain words instead. Apple may report this
validation error by email after a successful upload; confirm the build finishes processing
in App Store Connect before inviting testers.

Official TestFlight builds now enable `KINWALL_PUSH=1`, `KINWALL_APNS_ENV=production`,
`KINWALL_TIME_SENSITIVE=1`, and `KINWALL_ASSOCIATED_DOMAINS=1`. The local TestFlight script uses the
same flags. The plugin sets the matching entitlements and the native capability indicators.

Before uploading, enable Push Notifications, Time Sensitive Notifications, and Associated Domains
for the app's identifier on team `PPVX64R65G`. Automatic signing must regenerate a profile carrying
those capabilities. Hosted must run the matching server and controller changes with all four
`APNS_*` credentials configured. No private APNs key belongs in the app, build artifacts or Git.
The ordinary push registration is `PUT /api/push/native`; Live Activity tokens use their existing
endpoint. Verify both independently on a real phone after Apple finishes processing the build.

Check notification taps with the app both running and closed: an evening check-in opens the
person's Journal, a morning check-in opens their check-in on Home, and an Upkeep reminder opens
its item or job. Notification links keep their query parameters and must belong to the current
family; a notification from a different family must not navigate the app.

Associated domains cover hosted `kinwall.family` and its subdomains. Each known family, the apex
and `app.` serve `/.well-known/apple-app-site-association` directly as JSON. Apple may cache this
association; installing a build before the hosted response is live can delay links/passkeys.
Self-hosted sign-in continues through the system authentication sheet.

**Each release**

1. Build and upload: each release runs `.github/workflows/testflight.yml` (from release-please; or
   run it by hand from the Actions tab, with a tag or on a branch). It archives with automatic
   signing through an App Store Connect API key and uploads. It's skipped until the repository has
   the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the `.p8` contents) and `APPLE_TEAM_ID`;
   make the key under App Store Connect → Users and Access → Integrations with the **Admin** role,
   so signing can manage profiles and upload through App Store Connect. The workflow writes the key only after the
   npm and CocoaPods installs (npm runs no install scripts) and hands it only to the archive and
   upload steps; its actions are pinned to commit SHAs. From a Mac instead: `TEAM=<team ID>
   scripts/testflight.sh`. The local script stops if either the archive or export fails, including
   when Xcode output is piped through the log summary. Build numbers are
   `<major*10000 + minor*100 + patch>.<minutes since 1970>` in both, so they always go up within a
   version; the unsigned GitHub builds use the first
   part only and are never uploaded.
The release environment also requires `APPLE_SIGNING_P12_BASE64` and
`APPLE_SIGNING_P12_PASSWORD`. Export one existing **Apple Development** identity (certificate
and private key) for team `PPVX64R65G` as a password-protected `.p12`, encode it as base64, and
store both values as GitHub environment secrets. Do not commit the P12, password, private key,
or base64 text. An exported certificate without its private key cannot sign an archive.

Each runner imports that identity into a temporary keychain, verifies its team and validity,
and pins its fingerprint for every archive target. Missing or invalid signing secrets stop the
workflow before Xcode can request another development certificate. Automatic provisioning still
updates profiles; App Store export uses Apple's existing managed distribution signing. The
runner removes the P12 immediately after import and deletes the keychain after upload or failure.
Rotate the saved identity deliberately before it expires. Repeatedly revoking CI-created
certificates only clears the immediate limit and does not fix fresh-runner certificate churn.

2. (EAS instead: `eas build --platform ios --profile production`, then `eas submit --platform ios`.)
3. TestFlight: the build appears after processing; test internally, then add external testers
   (external testing needs a short beta review).
4. Submit for review in App Store Connect with:
   - screenshots (6.9" and 6.5" iPhone, 13" iPad, Apple Watch; generated from the demo),
   - review notes: "No account needed: tap **Try the demo** on the first screen" (the demo family),
     and a line on what the widgets, Live Activities and Watch app do,
   - "What's New" text from the changelog.
5. After approval, release manually or automatically.

Things review looks at for Kinwall: guideline 4.2 (more than a website; the native features cover
it), account deletion info (in iPhone Settings → Kinwall), no purchases or prices in the app
(payments are web only), and the push entitlement only in builds that use push (`KINWALL_PUSH=1`).

## Google Play (Android)

**Once**

1. A Google Play developer account (one-time fee; identity verification).
2. **Personal accounts must run a closed test first:** new personal developer accounts need a closed
   test with at least 12 testers opted in for 14 days in a row before they can publish to
   production. Plan for this; an organization account doesn't have the rule.
3. In Play Console, create the app with package `family.kinwall.app`.
4. Turn on Play App Signing (Google holds the app signing key; you keep an upload key). Make the
   upload key once with the `keytool` line at the top of `scripts/play-bundle.sh`, at
   `~/.kinwall/kinwall-upload.jks`, and back it and its password up: every upload must be signed
   with it. Lost or leaked, Play Console → App integrity → **Request upload key reset**.
5. Store listing: title, short and full description, icon, feature graphic, phone and tablet
   screenshots, privacy policy URL.
6. App content forms:
   - Data safety (match the iOS privacy label),
   - Content rating questionnaire,
   - Target audience: a family organizer used by parents and kids; if under-13s are a target, the
     Families policy applies, so answer carefully,
   - Health apps declaration (medications, check-ins and the Health tracker count; on Android also
     the medicine reminders and the Take now widget, which shows a count, never names),
   - Exact alarms: the app declares `USE_EXACT_ALARM` (Android 13 and later, granted at install) and
     `SCHEDULE_EXACT_ALARM` capped at Android 12L (`maxSdkVersion` 32). Play allows
     `USE_EXACT_ALARM` only for apps whose core function is a calendar, alarm clock or reminders,
     and asks for a declaration in App content → **Exact alarm permission**: say Kinwall is a
     family calendar whose event, leave-by and medicine reminders and cooking timers must fire at
     the set time. If Play turns it down, drop `USE_EXACT_ALARM` from `app.json` and
     `plugins/withKinwallNative.js` (withExactAlarms) and remove the `maxSdkVersion` cap; the alarms
     then fall back to inexact ones (possibly minutes late) unless the person allows **Alarms &
     reminders**,
   - No `SYSTEM_ALERT_WINDOW` (blocked in `app.json`), no full-screen intents, no
     `ACCESS_NOTIFICATION_POLICY`: Do Not Disturb for medicine is the person's own channel switch,
   - Ads: none.

**Each release**

1. Automatic: merging the release PR runs `.github/workflows/play.yml`, which builds the bundle and
   uploads it to the internal testing track (as a draft until the app's first review; then set the
   repository variable `PLAY_RELEASE_STATUS` to `completed`). It's skipped until the secrets listed at
   its top are set: the upload key (base64), its password, and a service account's JSON key.
2. By hand: `scripts/play-bundle.sh` writes a signed `.aab` to the Desktop (it asks for the upload
   key password); upload it in Play Console to a track. Version codes are minutes since 1970 in
   both, so they always go up.
3. Tracks: internal testing, then closed testing, then production (staged rollout is a good
   default).
4. Release notes from the changelog; submit for review (usually hours to a few days).

## Not in the stores

- Unsigned iOS and debug-signed Android builds on GitHub Releases, for testers and self-hosters.
  The debug-signed APK can't update a Play Store install, and the reverse.

Pairing QR links (`https://<family>.kinwall.family/#/pair?code=<six digits>`) must open the
connected family’s approval page in the app. Test both a cold launch and an already-running app.
Links for other families and malformed or duplicate codes are ignored. Opening the page never
approves a pairing; parent authentication and confirmation remain required.

Routine Mode also requires the App Group `group.family.kinwall.routine`, assigned to
`family.kinwall.app` and `family.kinwall.app.routine-monitor` on team `PPVX64R65G`. Both
identifiers need Family Controls distribution approval. Regenerate provisioning profiles after
assigning the group. Widgets, share and Watch widget target configs explicitly disable inherited
App Groups; these extensions keep using the shared Keychain and do not use the routine container.
