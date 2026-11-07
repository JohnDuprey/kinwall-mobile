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

## Android: mobile transport prepared, server work still required

Ordinary builds still use local reminders and do **not** receive immediate new-chore pushes.
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
This is a **proposed required endpoint**, absent from the referenced Kinwall server. A 404 or failed
registration leaves local scheduling enabled and never reports push ready. Raw FCM tokens must
never be posted to the APNs route, browser Web Push registration or Apple App Attest gateway.
The existing web server-settings path is exposed in configured builds; until the endpoint exists,
it cannot obtain an Android subscription or save New chores. Unconfigured builds retain the
local-reminder settings path, which has no New chores switch.

### Required server contract before enabling Android push in distributed builds

- Add authenticated `PUT /api/push/android`, accepting opaque FCM tokens (not the APNs hex regex).
  Return `{ push: boolean, delivery: 'direct' | 'unavailable', subscription: { id, deviceName,
  memberIds, prefs, createdAt, lastSuccessAt } }`, using the existing subscription schema.
- Reuse the subscription across token/access-key rotation via stable OAuth grant or paired-key
  identity, preserve preferences and followed members, and enforce child-owner targeting.
  Store the encrypted token with a transport-specific fingerprint, retire its previous sign-in,
  and default `newChores` to false for both existing and new registrations.
- Route FCM subscriptions through the same new-chore recipient selection as APNs/Web Push,
  including Anyone chores, creator device/person exclusion, feature switches and silent edits,
  imports, templates and inactive chores. Keep the single bell entry server-owned.
- Keep `PATCH` merge semantics and `DELETE /api/push/subscriptions/{id}` compatible. Sign-out,
  permission revocation and turning off notifications use this DELETE while credentials remain
  valid; a late registration after sign-out is deleted by the serialized session coordinator.
- Configure an FCM HTTP v1 sender with server-side credentials for the same Firebase project.
  Remove retired tokens on FCM UNREGISTERED, not on temporary failures. No keys enter the app.
- Return `push: true` only when the full native alert path works. As on iOS, event reminders stay
  local (`eventReminders: false` enforced on register/PATCH), while medicine and daily chore
  reminders transfer to the server only after confirmed readiness. A chore-only sender must
  **not** return true under this contract: doing so would stop local medicine/daily reminders.
- Update the web native-push explanation and unavailable-delivery text to be platform-aware:
  the current web strings say “Apple push” for every native device. Translate those web changes
  alongside the endpoint. The existing New chores switch itself already saves the right preference.

For the installed expo-notifications receiver, send a visible FCM HTTP v1 message with localized
`notification.title` = “New chore” and `notification.body` = chore title. Use
`android.priority: 'HIGH'`, `android.ttl: '0s'`, and
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
rotation and sign-out delivery must be verified after the endpoint and credentials are available.
No real household pushes are required for unit tests or builds.
