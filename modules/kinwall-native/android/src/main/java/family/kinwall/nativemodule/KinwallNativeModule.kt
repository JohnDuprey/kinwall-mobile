package family.kinwall.nativemodule

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import org.json.JSONObject

/** Android's KinwallNative (modules/kinwall-native/index.ts): the keys (Keychain.kt), the
 * countdowns (Countdowns.kt) and the notification channels (Channels.kt). Widgets render from
 * JavaScript on Android (reloadWidgets asks Android to redraw them) and there's no Watch; there's
 * no push, so "activityToken" never fires. */
class KinwallNativeModule : Module() {
  private val context get() = requireNotNull(appContext.reactContext)

  override fun definition() = ModuleDefinition {
    Name("KinwallNative")
    Events("watchStateChanged", "activityToken")

    // Edge to edge (Android 15 and later) the window no longer shrinks for the keyboard
    // (adjustResize), so a field at the bottom of the page (shopping mode's Add an item) would sit
    // under it. The content makes room itself: the keyboard's height less the navigation bar the
    // screens already keep clear of. The insets pass on untouched.
    OnCreate {
      Channels.ensure(context)
      val activity = appContext.currentActivity ?: return@OnCreate
      activity.runOnUiThread {
        ViewCompat.setOnApplyWindowInsetsListener(activity.findViewById<View>(android.R.id.content)) { view, insets ->
          val keyboard = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
          val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars()).bottom
          view.setPadding(0, 0, 0, maxOf(0, keyboard - bars))
          insets
        }
      }
    }

    // A contact shared to the app: MainActivity (plugins/withKinwallNative.js) leaves its vCard here.
    Function("takeSharedContacts") {
      val file = java.io.File(context.cacheDir, "shared-contacts.vcf")
      if (!file.exists()) null else file.readText().also { file.delete() }
    }

    AsyncFunction("keychainGet") { service: String, _: Boolean -> Keychain.get(context, service) }
    AsyncFunction("keychainSet") { service: String, _: Boolean, value: String? ->
      if (!Keychain.set(context, service, value)) throw IllegalStateException("Couldn't save $service")
    }
    Function("reloadWidgets") { Widgets.reload(context) }
    Function("watchAppInstalled") { false }
    Function("updateWatch") { _: Map<String, Any?> -> }

    AsyncFunction("activitySet") { kind: String, payload: String, colors: Map<String, String>? ->
      Countdowns.set(context, kind, payload, colors?.let { JSONObject(it as Map<*, *>).toString() })
    }
    AsyncFunction("activityEnd") { kind: String? -> Countdowns.end(context, kind) }
    AsyncFunction("activityEndStale") { Countdowns.endStale(context) }
    Function("activitiesEnabled") { Countdowns.enabled(context) }
    // Before src/reminders.ts schedules on them; and a channel's page in Android Settings (the web
    // app's "Let medicine through Do Not Disturb", through src/WebShell.tsx).
    AsyncFunction("ensureChannels") { Channels.ensure(context) }
    Function("openNotificationSettings") { channel: String? -> Channels.openSettings(context, channel) }
    // Android 13 and later: offer a Quick Settings tile ("groceries", "night"); Android's answer.
    AsyncFunction("addTile") { name: String, promise: expo.modules.kotlin.Promise -> Tiles.request(context, name) { promise.resolve(it) } }
    AsyncFunction("leaveBySchedule") { alarms: String -> Countdowns.schedule(context, alarms) }
    // The contact sheet's Video call (src/links.ts meetCall): a Google Meet video call to the number,
    // with Meet's call intent (the one Google's Contacts and Phone apps start). Without Meet, its
    // Play Store page (the web one when there's no Play Store).
    Function("videoCall") { number: String ->
      val activity = appContext.currentActivity ?: return@Function
      val meet = "com.google.android.apps.tachyon"
      val tries = listOf(
        Intent("$meet.action.CALL", Uri.fromParts("tel", number, null)).setPackage(meet),
        Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$meet")),
        Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$meet")),
      )
      activity.runOnUiThread {
        for (intent in tries) try { activity.startActivity(intent); break } catch (_: ActivityNotFoundException) {}
      }
    }
    // Edge to edge, the navigation bar is see-through: its buttons follow the page's colors, not
    // the system's light or dark mode (expo-status-bar only does the status bar).
    Function("navigationBar") { dark: Boolean ->
      val activity = appContext.currentActivity ?: return@Function
      activity.runOnUiThread { WindowInsetsControllerCompat(activity.window, activity.window.decorView).isAppearanceLightNavigationBars = !dark }
    }
  }
}
