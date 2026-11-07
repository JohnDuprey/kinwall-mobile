# New chore notifications

New chores is a per-device switch in **Settings → Notifications**, off by default. The web
settings save `prefs.newChores` with `PATCH /api/push/subscriptions/{id}`. The shell supplies only
its own subscription ID and delivery readiness through the trusted bridge; it never exposes a
push token or rewrites preferences on registration, reload or token renewal. Followed members,
child ownership and creator exclusion remain server decisions using the personal sign-in, not
the widgets' shared family key.

On supported iOS push builds, the server feature in Kinwall commit
`c4236757bc794a0b9892e2954e25c6bac12031d8` already supplies delivery and the translated setting.
Tapping its `/#/chores` URL opens Chores on the current family. APNs registration and App Attest
remain unchanged. Bridge metadata is now initialized again on every web document load, including
reconnects; expired gateway registrations report not ready.

## Android: FCM integration

Firebase-configured builds register with Kinwall and receive native FCM alerts when the server
has the matching implementation and credentials. Builds without Firebase configuration, older
servers (404), and servers reporting unavailable delivery keep local reminders and do **not**
receive immediate new-chore pushes.
There is no polling substitute and no new chore alarm. Turning on Android's daily Chores channel
does not enable new-chore messages. The separate **New chores** (`new_chores`) channel controls
sound/presentation, while `prefs.newChores` controls whether the server sends anything. Its channel
name and description have English and German resources, matching the web app's bundled locales;
notification title/body and the settings switch use the server/web translations.

To build the mobile FCM path, supply an untracked Firebase Android client configuration for
`family.kinwall.app`:

```sh
export KINWALL_GOOGLE_SERVICES_FILE=/absolute/path/google-services.json
npx expo prebuild -p android --clean
npx expo run:android
```

Keep the variable set during prebuild, Metro and the native build so the embedded Expo config
matches the Firebase-enabled native app. The page cannot change it. The Expo config sets
`android.googleServicesFile` and `extra.androidNativePush`. No Firebase file, service-account key,
signing identity or token belongs in git. This uses the existing expo-notifications FCM receiver
and `getDevicePushTokenAsync`, not Expo Push Service. The build must have Google Play services.
See Expo's [direct FCM guide](https://docs.expo.dev/push-notifications/sending-notifications-custom/)
and [Firebase configuration](https://docs.expo.dev/push-notifications/fcm-credentials/).

A configured build attempts **PUT /api/push/android** with `{ token, deviceName: 'Kinwall Android' }`.
Kinwall commit
`d5c69a89489a2be44be481b928af38ff250080d5` implements this endpoint and the full native FCM
alert sender. A 404 or failed first registration leaves local scheduling enabled and never reports
push ready; a temporary renewal failure preserves an already working registration. Raw FCM tokens must
never be posted to the APNs route, browser Web Push registration or Apple App Attest gateway.
The web server-settings path is exposed in configured builds. Successful registration supplies
the subscription ID so the web can save New chores and followed members directly on the server.
Unconfigured builds retain the local-reminder settings path, which has no New chores switch.

### Build configuration in CI and EAS

The unsigned Android APK workflow and Google Play bundle workflow accept the optional repository
Actions secret **KINWALL_GOOGLE_SERVICES_JSON**, containing the Firebase **Android client**
`google-services.json` for `family.kinwall.app`. The release workflow forwards it to the reusable
APK workflow; the Play workflow inherits it. Do not use the FCM service-account JSON or Play upload
credentials for this secret. `scripts/android-firebase-ci.mjs` validates the client identity, rejects
service-account keys, writes only to the runner's temporary directory with mode 0600, and exports
`KINWALL_GOOGLE_SERVICES_FILE` for both prebuild and Gradle's JavaScript bundle. It never prints the
configuration. Cleanup removes both temporary and generated native copies. A missing secret
produces a local-reminder build; malformed or mismatched configuration fails the build.

For local builds, keep `KINWALL_GOOGLE_SERVICES_FILE` in an ignored `.env.local` or export it for
the whole build. For EAS, create a file environment variable named `KINWALL_GOOGLE_SERVICES_FILE`
with the client file in the environment selected by the build profile. All profiles use the same
opt-in app config; none embeds a developer's local path. The client config is packaged into the
Android app and is distinct from the server's private FCM signing credentials.

### Implemented server contract

- Authenticated `PUT /api/push/android`, accepting opaque FCM tokens (not the APNs hex regex).
  Returns `{ push: boolean, delivery: 'direct' | 'unavailable', subscription: { id, deviceName,
  memberIds, prefs, createdAt, lastSuccessAt } }`, using the existing subscription schema.
- Reuses the subscription across token/access-key rotation via stable OAuth grant or paired-key
  identity, preserving preferences and followed members and enforcing child-owner targeting.
  Stores the encrypted token with a transport-specific fingerprint, retires its previous sign-in,
  and defaults `newChores` to false for both existing and new registrations.
- Routes FCM subscriptions through the same new-chore recipient selection as APNs/Web Push,
  including Anyone chores, creator device/person exclusion, feature switches and silent edits,
  imports, templates and inactive chores. The single bell entry stays server-owned.
- Keeps `PATCH` merge semantics and `DELETE /api/push/subscriptions/{id}` compatible. Sign-out,
  permission revocation and turning off notifications use this DELETE while credentials remain
  valid; a late registration after sign-out is deleted by the serialized session coordinator.
- Uses an FCM HTTP v1 sender with server-side credentials for the same Firebase project.
  Removes retired tokens on FCM UNREGISTERED, not on temporary failures. No keys enter the app.
- Returns `push: true` only with the full native alert sender configured. This reports capability,
  not provider or device health. As on iOS, event reminders stay
  local (`eventReminders: false` enforced on register/PATCH), while medicine and daily chore
  reminders transfer to the server only after confirmed readiness. A chore-only sender must
  **not** return true under this contract: doing so would stop local medicine/daily reminders.
- The web native-push explanation and unavailable-delivery text are platform-aware, with German
  translations. The New chores switch saves the existing server preference.

For the installed expo-notifications receiver, send a visible FCM HTTP v1 message with localized
`notification.title` = “New chore” and `notification.body` = chore title. Use
`android.priority: 'HIGH'`, `android.ttl: '3600s'` (a TTL of 0 drops the alert while the device sleeps), and
`android.notification: { channel_id: 'new_chores', tag: 'chore:new:<id>', sound: 'default' }`.
Set `data.tag` to that same tag (Expo's foreground identifier), and set **`data.body` to a JSON
string** containing `{ url: '/#/chores', server: '<canonical family origin>' }`. Expo decodes this
body into `content.data`, which the existing tap handler validates against the selected family.
Do not use `data.route` or an action category: a new-chore notification opens Chores and does not
mark it done. Include `server` so a notification from a former family cannot open the new family.

A notification + data message uses FCM's visible background delivery and Expo's foreground
presentation. Do not send an additional local copy or rely on a foreground/background polling
interval. Delivery remains subject to notification permission, channel settings, network, Android
battery restrictions and force-stop behavior. Physical-device background, cold-start tap, token
rotation and sign-out delivery still require verification with the deployed endpoint and credentials.
No real household pushes are required for unit tests or builds.

## Android: self-hosted push gateway

A server without its own FCM credentials can deliver full alerts to the official Play build
through `push.kinwall.family`. It is a separate Android protocol: Android never uses the Apple
App Attest routes, and raw FCM tokens never go to them.

1. `PUT /api/push/android` answers `gatewayAvailable: true` when the server supports the gateway
   and has a valid canonical `PUBLIC_URL`. Absent or false (older servers) means the app does not
   enroll. A direct sender (`delivery: 'direct'`) always wins; the app then revokes any gateway
   credential it held for that origin, including a previous FCM token after rotation. Other
   origins keep their capabilities. Cleanup is persisted before the revoke request; offline cleanup
   retries on the next sync without repeating the successful direct registration or enrolling a
   gateway capability. A direct response with `push: false` does not remove a working capability.
2. Otherwise the shell asks the gateway for a challenge (`POST /v1/android/enrollment/challenge`
   with the standard-base64 DER SPKI of a P-256 key and `{ token, server, kind: 'android-alert' }`).
   Before any proof it checks the returned `clientData` is exactly
   `{"protocol":"kinwall-android-push-v1","challenge":<64 hex>,"keyId":<hex SHA-256 of the SPKI>,
   "tokenHash":<hex SHA-256 of the raw, case-sensitive FCM token>,"server":<its URL.origin>,
   "kind":"android-alert"}` in that order, and that `requestHash` is the unpadded base64url
   SHA-256 of that string.
3. Native code (`PushGateway.kt`) signs the exact UTF-8 `clientData` with the Keystore key
   (SHA256withECDSA, converted to raw 64-byte r‖s, base64url) and requests a **standard Play
   Integrity** token for the same hash, computing it again itself. Each Play step times out after
   30 s. `POST /v1/android/enrollment/register` returns `{ id, credential, expiresAt }`; the
   credential is `android-v1.<id>.<64 hex>` and lasts at most 30 days.
4. The app sends `gateway: { credential }` with the next `PUT /api/push/android`. Readiness still
   needs `push: true` with a future `gatewayExpiresAt`; until then medicine and daily reminders stay
   local. Renewal starts within 5 minutes of expiry with a fresh challenge and proof.

The gateway, not the app, decides trust: it verifies the Play verdict (recognized app, licensed,
device integrity, signing certificate, fresh and bound to the request hash). The Keystore signature
only proves this install holds the key. The key never leaves the Keystore. Credentials live in
`expo-secure-store`, encrypted with a Keystore key. Enrollment, renewal, sign-out and token rotation
run one at a time; replaced credentials go to a durable revoke queue (`DELETE
/v1/android/registration`) retried on the next sync, so sign-out offline still completes. None of this is reachable from
the web page.

### Build prerequisites

- A Google Cloud project linked to the app in Play Console (**App integrity → Play Integrity
  API**), with the API enabled. Its project **number** (not the Firebase project ID) goes in
  `KINWALL_PLAY_INTEGRITY_PROJECT_NUMBER` at prebuild, alongside `KINWALL_GOOGLE_SERVICES_FILE`;
  `plugins/withAndroidPushGateway.js` writes it into the manifest. Without it, or without Firebase,
  the build has no gateway.
- The app installed from Google Play (internal testing track is enough) and signed by Play App
  Signing, so the gateway can match the certificate. Debuggable builds report the gateway
  unsupported; sideloaded installs fail Google's licensing verdict.
- A device with Google Play services and a current Play Store.

Do not use the earlier internal draft's version code `29901030` as the gateway minimum:
main's non-gateway build `29901062` is newer. The gateway minimum must be the first configured,
gateway-enabled **main** build with a version code above `29901062`, after Play linking and the
release gates are verified. Confirming a Firebase project does not confirm Play Integrity linking;
leave `KINWALL_PLAY_INTEGRITY_PROJECT_NUMBER` unset until that link is confirmed. This does not
change app versions or upload a build.

Not yet verified: a real Play verdict on a physical device against the deployed gateway, and
end-to-end delivery through it. Tests use fake proofs and mocked HTTP only.

## Verification and rollout status

The Android credential lifecycle is merged in [core PR85](https://github.com/JohnDuprey/kinwall/pull/85)
(`dc6086d`); its [public API contract](https://github.com/JohnDuprey/kinwall/blob/main/docs/integrations/rest-api.md)
defines readiness, token rotation and credential cleanup. A merged change or successful mobile
build does not establish deployed provider/device delivery. No deployment or real household sends
were performed for these review fixes. Self-hosters need the current Kinwall server, canonical
`PUBLIC_URL`, and `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` for the same Firebase project.

Mobile logic tests cover transport gates, personal reminder identity, subscription metadata on
reload/expiry, token/access-key rotation, cleanup after a late sign-out registration, and same-family
tap routing. The installed Expo receiver decodes `data.body` for foreground and background taps;
FCM owns visible background delivery and the existing Expo handler owns foreground presentation.
No second local notification is scheduled for a remote new chore. Full provider/device delivery,
Google IAM acceptance and permission/channel/battery/force-stop behavior remain unverified; mocks
and a successful Firebase-enabled Android build do not establish end-to-end delivery.
