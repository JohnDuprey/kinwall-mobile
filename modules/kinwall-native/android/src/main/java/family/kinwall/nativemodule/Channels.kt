package family.kinwall.nativemodule

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationManagerCompat

/**
 * One notification channel per purpose, so each can be tuned in Android Settings → Apps → Kinwall →
 * Notifications. A channel's id is permanent and its settings belong to the person once it exists,
 * so these ids never change; creating one that exists only updates its name and description.
 *
 * - `reminders` Event reminders (src/reminders.ts; the id expo-notifications has used since the start)
 * - `leave_by` Leave-by: the leave-by and start-prep countdowns and "Leave by…" reminders
 * - `medicine` Medicine: reminders and the due-dose countdown, on the person's own phone. A parent
 *   can let it through Do Not Disturb with the channel's own switch (openSettings), no permission needed
 * - `chores` Chores: the daily chore nudge. Opt-in, so it starts off (turned on in its settings)
 * - `new_chores` New chores: immediate server pushes, gated by subscription prefs.newChores
 * - `countdowns` Timers and countdowns: the cooking timer's countdown and the shopping trip
 * - `cooking_timers` Cooking timers: rings when a timer is up (Countdowns.ring)
 *
 * Moving over: the leave-by and medicine countdowns used to be on `countdowns`. A phone that had
 * turned that channel off gets Leave-by off too; Medicine starts on, since missing a dose matters more.
 */
object Channels {
  const val REMINDERS = "reminders"
  const val LEAVE_BY = "leave_by"
  const val MEDICINE = "medicine"
  const val CHORES = "chores"
  const val NEW_CHORES = "new_chores"
  const val COUNTDOWNS = "countdowns"
  const val COOKING = "cooking_timers"
  val ALL = listOf(REMINDERS, LEAVE_BY, MEDICINE, CHORES, NEW_CHORES, COUNTDOWNS, COOKING)

  private const val HIGH = NotificationManagerCompat.IMPORTANCE_HIGH
  private const val DEFAULT = NotificationManagerCompat.IMPORTANCE_DEFAULT
  private const val NONE = NotificationManagerCompat.IMPORTANCE_NONE

  fun ensure(c: Context) {
    if (Build.VERSION.SDK_INT < 26) return
    val nm = NotificationManagerCompat.from(c)
    val countdownsOff = nm.getNotificationChannelCompat(COUNTDOWNS)?.importance == NONE
    fun make(id: String, importance: Int, name: String, description: String, extra: NotificationChannelCompat.Builder.() -> Unit = {}) {
      // A new channel's first importance is the only one we set; after that it's the person's.
      nm.createNotificationChannel(NotificationChannelCompat.Builder(id, importance).setName(name).setDescription(description).apply(extra).build())
    }
    make(REMINDERS, HIGH, "Event reminders", "Before events, at the times each event asks for")
    make(LEAVE_BY, if (countdownsOff && nm.getNotificationChannelCompat(LEAVE_BY) == null) NONE else HIGH, "Leave-by", "When to leave or start prep, and the countdown to it")
    make(MEDICINE, HIGH, "Medicine", "Your own doses on this phone. To let them through Do Not Disturb, turn on Override Do Not Disturb here.")
    make(CHORES, NONE, "Chores", "A morning nudge with your chores left today. Off until you turn it on here.")
    make(NEW_CHORES, HIGH, c.getString(R.string.kinwall_new_chores), c.getString(R.string.kinwall_new_chores_description))
    make(COUNTDOWNS, DEFAULT, "Timers and countdowns", "Cooking timers and shopping trips")
    val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    make(COOKING, HIGH, "Cooking timers", "Rings when a cooking timer is done") {
      setSound(sound, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
      setVibrationEnabled(true)
      setVibrationPattern(longArrayOf(0, 600, 400, 600))
    }
  }

  /** Android's page for one channel (its sound, Do Not Disturb override…), or the app's
   * notification settings for an unknown one. */
  fun openSettings(c: Context, channel: String?) {
    ensure(c)
    val intent = if (Build.VERSION.SDK_INT >= 26 && channel in ALL) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_CHANNEL_ID, channel)
      else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
    c.startActivity(intent.putExtra(Settings.EXTRA_APP_PACKAGE, c.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  }
}
