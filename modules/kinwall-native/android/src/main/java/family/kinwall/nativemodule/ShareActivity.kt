package family.kinwall.nativemodule

import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.net.Uri
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.os.Bundle
import android.text.InputType
import android.text.format.DateFormat
import android.util.TypedValue
import android.view.MotionEvent
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.SwitchCompat
import androidx.core.content.IntentCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/** "Kinwall" in Android's share sheet: sends what's shared to the family's Kinwall (POST api/share,
 * Share.kt) in a small sheet over the app it came from, like the iOS share extension
 * (targets/share). A link goes as it is (Kinwall reads the page). A photo or some text is read on the
 * device (ShareReader.kt): an ISBN barcode goes as a book straight away; otherwise the sheet shows a
 * guess ("Looks like a menu: …", from Gemini Nano where the phone has it, else from the dates,
 * places and phone numbers in it) with Add to Kinwall and "Not a menu?", or asks "What is this?".
 * An event shows what Kinwall read, to fix and add to a calendar here (Add to calendar) or open in
 * the app (Open in Kinwall), like the iOS sheet's EventReview. A book to pick opens in the app;
 * anything saved shows Kinwall's line with Open, and the sheet closes itself after about 3 s unless
 * it's touched. A contact shared as text goes on to MainActivity's contact review
 * (plugins/withKinwallNative.js), as before. */
class ShareActivity : AppCompatActivity() {
  private val scope = MainScope()
  private lateinit var spinner: ProgressBar
  private lateinit var label: TextView
  private lateinit var add: Button
  private lateinit var notThat: Button
  private lateinit var choices: LinearLayout
  private lateinit var done: Button
  private lateinit var openSaved: Button
  private var savedResult: Share.Result? = null
  private var touched = false
  // The event's fields (eventForm): the household's day and HH:MM times, as Kinwall reads them.
  private lateinit var eventForm: LinearLayout
  private lateinit var title: EditText
  private lateinit var place: EditText
  private lateinit var notes: EditText
  private lateinit var dayButton: Button
  private lateinit var allDay: SwitchCompat
  private lateinit var startButton: Button
  private lateinit var endButton: Button
  private lateinit var calendarLabel: TextView
  private lateinit var calendarPicker: Spinner
  private lateinit var formError: TextView
  private lateinit var addToCalendar: Button
  private lateinit var openInKinwall: Button
  private var day = ""
  private var start = "09:00"
  private var end = "10:00"
  private var calendars = listOf<Share.FamilyCalendar>()

  private sealed interface Choice { data object Add : Choice; data class Pick(val kind: Share.Kind) : Choice; data object Save : Choice; data object Open : Choice }
  private var waiting: ((Choice) -> Unit)? = null
  private suspend fun wait(): Choice = suspendCancellableCoroutine { c -> waiting = { waiting = null; c.resume(it) } }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    if (forwardContact()) return
    setFinishOnTouchOutside(false)
    setContentView(layout())
    val width = minOf(resources.displayMetrics.widthPixels - dp(32), dp(440))
    window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
    if (savedInstanceState == null) scope.launch { run() } else finish() // rotated mid-share: start over
  }

  /** Any touch keeps a saved result's sheet open (it closes itself otherwise). */
  override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
    touched = true
    return super.dispatchTouchEvent(ev)
  }

  override fun onDestroy() {
    scope.cancel()
    super.onDestroy()
  }

  /** A vCard shared as plain text: the app's contact review takes it (MainActivity's shareContacts). */
  private fun forwardContact(): Boolean {
    if (intent.getStringExtra(Intent.EXTRA_TEXT)?.contains("BEGIN:VCARD", ignoreCase = true) != true) return false
    val main = packageManager.getLaunchIntentForPackage(packageName)?.component ?: return false
    startActivity(Intent(intent).setComponent(main).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    finish()
    return true
  }

  private suspend fun run() {
    val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
    val image = if (intent.type?.startsWith("image/") != true) null
      else if (intent.action == Intent.ACTION_SEND_MULTIPLE) IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.firstOrNull()
      else IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
    val link = text?.let(Share::linkIn)
    when {
      link != null -> send(Share.Request(url = link), "Reading the page…")
      text != null -> { busy("Reading it…"); sendWords(text) }
      image != null -> {
        busy("Reading the photo…")
        val read = ShareReader.read(this, image) ?: return result("Kinwall couldn't open this photo.")
        if (read.isbn != null) return send(Share.Request(kind = Share.Kind.BOOK, text = read.isbn), "Adding the book…")
        sendWords(read.text ?: return result("Kinwall couldn't find any words in this photo."))
      }
      else -> result("Share a link, a photo, some text or a contact to add it to Kinwall.")
    }
  }

  /** A photo's words or shared text: a guess to confirm, else "What is this?". An event goes to its
   * fields (checkEvent) with the words as read under the model's lines. */
  private suspend fun sendWords(raw: String) {
    val found = scope.async { ShareReader.entities(raw) }
    val model = ShareReader.ask(Share.guessPrompt(raw))?.let(Share::guess)
    val guess = model ?: Share.guessKind(found.await(), raw)?.let { it to Share.withHeaders(it, found.await(), raw) }
    var kind: Share.Kind
    var text: String? = null
    if (guess != null && guess.first == Share.Kind.EVENT) {
      kind = guess.first; text = guess.second
    } else if (guess != null) {
      spinner.visibility = View.GONE
      label.text = Share.guessLine(guess.first, guess.second)
      notThat.text = Share.notLabel(guess.first)
      show(add, notThat, done)
      when (val c = wait()) {
        is Choice.Pick -> { kind = c.kind; if (c.kind == guess.first) text = guess.second }
        else -> { kind = guess.first; text = guess.second }
      }
    } else {
      showChoices()
      kind = (wait() as Choice.Pick).kind
    }
    show()
    if (text == null) {
      busy("Reading it…")
      text = ShareReader.ask(Share.prompt(kind, raw)) ?: Share.withHeaders(kind, found.await(), raw)
    }
    if (kind == Share.Kind.EVENT) return checkEvent(Share.eventText(text, raw), raw, guess?.first == Share.Kind.EVENT)
    send(Share.Request(kind = kind, text = text), "Adding to Kinwall…")
  }

  /** An event: what Kinwall read and the calendars to add it to, to fix and add here, or open in the
   * app. A Kinwall too old to say what it read opens the app's event sheet, as before. */
  private suspend fun checkEvent(text: String, raw: String, guessed: Boolean) {
    busy("Reading the event…")
    val cals = scope.async(Dispatchers.IO) { calendars(this@ShareActivity) }
    val read = withContext(Dispatchers.IO) { post(this@ShareActivity, Share.Request(kind = Share.Kind.EVENT, text = text)) }
    if (read is Share.Outcome.Failed) return result(read.message)
    val r = (read as Share.Outcome.Done).result
    val draft = r.event ?: return openInApp(r)
    calendars = cals.await().orEmpty()
    fill(draft)
    spinner.visibility = View.GONE
    label.text = if (guessed) "Looks like an event" else "Check the event"
    notThat.text = Share.notLabel(Share.Kind.EVENT)
    done.text = "Cancel"
    while (true) {
      formError.visibility = View.GONE
      show(eventForm, *listOfNotNull(addToCalendar.takeIf { calendars.isNotEmpty() }, openInKinwall, notThat.takeIf { guessed }, done).toTypedArray())
      when (val c = wait()) {
        Choice.Save -> {
          val event = draft() ?: continue
          setBusy(true)
          val o = withContext(Dispatchers.IO) { post(this@ShareActivity, Share.Request(kind = Share.Kind.EVENT, event = event, save = true, calendarId = calendars[calendarPicker.selectedItemPosition].id)) }
          setBusy(false)
          when (o) {
            is Share.Outcome.Failed -> { formError.text = o.message; formError.visibility = View.VISIBLE; show(eventForm, addToCalendar, openInKinwall, done); continue }
            is Share.Outcome.Done -> { label.text = ""; return saved(o.result) }
          }
        }
        Choice.Open -> {
          val event = draft() ?: continue
          setBusy(true)
          when (val o = withContext(Dispatchers.IO) { post(this@ShareActivity, Share.Request(kind = Share.Kind.EVENT, event = event)) }) {
            is Share.Outcome.Failed -> return result(o.message)
            is Share.Outcome.Done -> return openInApp(o.result)
          }
        }
        is Choice.Pick -> { // Not an event? showed "What is this?": on as if picked first
          val kind = c.kind
          busy("Reading it…")
          val tidied = ShareReader.ask(Share.prompt(kind, raw))
          if (kind == Share.Kind.EVENT) return checkEvent(Share.eventText(tidied, raw), raw, false)
          return send(Share.Request(kind = kind, text = tidied ?: Share.withHeaders(kind, ShareReader.entities(raw), raw)), "Adding to Kinwall…")
        }
        Choice.Add -> {}
      }
    }
  }

  /** The fields as an event to send, or null (and a word why) without a title. */
  private fun draft(): Share.EventDraft? {
    val t = title.text.toString().trim()
    if (t.isEmpty()) { formError.text = "Add the event's title."; formError.visibility = View.VISIBLE; return null }
    return Share.EventDraft(t, day, start.takeIf { !allDay.isChecked }, end.takeIf { !allDay.isChecked }, place.text.toString().trim().takeIf { it.isNotEmpty() }, notes.text.toString().trim().takeIf { it.isNotEmpty() })
  }

  private fun fill(draft: Share.EventDraft) {
    title.setText(draft.title.orEmpty())
    place.setText(draft.place.orEmpty())
    notes.setText(draft.notes.orEmpty())
    day = draft.date ?: SimpleDateFormat("yyyy-MM-dd", Locale.US).format(System.currentTimeMillis()) // none read: today, to change
    start = draft.time ?: "09:00"
    end = draft.end ?: Share.movedEnd("00:00", start, "01:00")
    allDay.isChecked = draft.time == null
    calendarPicker.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, calendars.map { it.name }).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
    calendarLabel.visibility = if (calendars.isEmpty()) View.GONE else View.VISIBLE
    calendarPicker.visibility = calendarLabel.visibility
    showWhen()
  }

  /** The date and times on their buttons, in the phone's style; the times only when it isn't all day. */
  private fun showWhen() {
    val utc = TimeZone.getTimeZone("UTC")
    fun parse(s: String) = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply { timeZone = utc }.parse(s)!!
    val time = (DateFormat.getTimeFormat(this) as SimpleDateFormat).apply { timeZone = utc }
    dayButton.text = SimpleDateFormat("EEE, MMM d, yyyy", Locale.getDefault()).apply { timeZone = utc }.format(parse("$day 00:00"))
    startButton.text = "Starts  " + time.format(parse("$day $start"))
    endButton.text = "Ends  " + time.format(parse("$day $end"))
    startButton.visibility = if (allDay.isChecked) View.GONE else View.VISIBLE
    endButton.visibility = startButton.visibility
  }

  private fun setBusy(on: Boolean) {
    spinner.visibility = if (on) View.VISIBLE else View.GONE
    for (v in listOf(title, place, notes, dayButton, allDay, startButton, endButton, calendarPicker, addToCalendar, openInKinwall, notThat, done)) v.isEnabled = !on
  }

  private suspend fun send(request: Share.Request, reading: String) {
    busy(reading)
    when (val o = withContext(Dispatchers.IO) { post(this@ShareActivity, request) }) {
      is Share.Outcome.Failed -> result(o.message)
      is Share.Outcome.Done -> if (o.result.needsReview) openInApp(o.result) else saved(o.result)
    }
  }

  /** Opens a result in the app's web view (src/links.ts routeFor, to=shared) and closes the sheet. */
  private fun openInApp(r: Share.Result) {
    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Share.appLink(r.link))).setPackage(packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    finish()
  }

  /** Saved: Kinwall's line with Open and Done; the sheet closes itself after about 3 s unless it's touched. */
  private suspend fun saved(r: Share.Result) {
    result(r.summary)
    savedResult = r
    show(openSaved, done)
    touched = false
    delay(3000)
    if (!touched) finish()
  }

  // --- The sheet ----------------------------------------------------------------------------------

  private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

  private fun button(text: String, filled: Boolean, onClick: () -> Unit) =
    Button(this, null, 0, if (filled) androidx.appcompat.R.style.Widget_AppCompat_Button_Colored else androidx.appcompat.R.style.Widget_AppCompat_Button_Borderless_Colored).apply {
      this.text = text
      isAllCaps = false
      textSize = 16f
      minHeight = dp(48)
      minimumHeight = dp(48)
      if (filled) {
        backgroundTintList = ColorStateList.valueOf(getColor(R.color.kinwall_share_fill))
        setTextColor(Color.WHITE)
      } else {
        setTextColor(getColor(R.color.kinwall_share_accent))
      }
      setOnClickListener { onClick() }
      layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(4) }
    }

  private fun layout(): View {
    spinner = ProgressBar(this)
    label = TextView(this).apply {
      text = "Opening in Kinwall…"
      setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Medium)
      setTextColor(getColor(R.color.kinwall_share_text))
      gravity = Gravity.CENTER
      setPadding(0, dp(12), 0, dp(12))
    }
    add = button("Add to Kinwall", true) { waiting?.invoke(Choice.Add) }
    notThat = button("", false) { showChoices() }
    choices = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      listOf("Restaurant" to Share.Kind.RESTAURANT, "Book" to Share.Kind.BOOK, "Event" to Share.Kind.EVENT).forEach { (title, kind) ->
        addView(button(title, false) { waiting?.invoke(Choice.Pick(kind)) })
      }
    }
    done = button("Cancel", false) { finish() }
    openSaved = button("Open", false) { savedResult?.let(::openInApp) }
    addToCalendar = button("Add to calendar", true) { waiting?.invoke(Choice.Save) }
    openInKinwall = button("Open in Kinwall", false) { waiting?.invoke(Choice.Open) }
    eventForm = eventForm()
    show()
    return ScrollView(this).apply {
      addView(LinearLayout(this@ShareActivity).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        setPadding(dp(24), dp(24), dp(24), dp(16))
        listOf(spinner, label, eventForm, add, addToCalendar, openInKinwall, notThat, choices, openSaved, done).forEach(::addView)
      })
    }
  }

  /** The event's fields: Title, the date, All day, Starts and Ends, Place, Notes, then Calendar. */
  private fun eventForm(): LinearLayout {
    val text = getColor(R.color.kinwall_share_text)
    val dim = getColor(R.color.kinwall_share_dim)
    fun caption(s: String) = TextView(this).apply { this.text = s; textSize = 13f; setTextColor(dim); setPadding(0, dp(10), 0, 0) }
    fun field(hint: String, lines: Int) = EditText(this).apply {
      this.hint = hint; textSize = 16f; setTextColor(text); setHintTextColor(dim); minHeight = dp(48)
      inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or (if (lines > 1) InputType.TYPE_TEXT_FLAG_MULTI_LINE else 0)
      maxLines = lines
      backgroundTintList = ColorStateList.valueOf(getColor(R.color.kinwall_share_accent))
    }
    fun picker(onClick: () -> Unit) = button("", false, onClick).apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL; setTextColor(text) }
    title = field("Title", 1)
    place = field("Place", 3)
    notes = field("What to bring, how to RSVP", 6)
    dayButton = picker {
      val (y, m, d) = day.split('-').map(String::toInt)
      DatePickerDialog(this, { _, yy, mm, dd -> day = "%04d-%02d-%02d".format(yy, mm + 1, dd); showWhen() }, y, m - 1, d).show()
    }
    fun timeDialog(of: String, set: (String) -> Unit) =
      TimePickerDialog(this, { _, h, m -> set("%02d:%02d".format(h, m)); showWhen() }, of.take(2).toInt(), of.takeLast(2).toInt(), DateFormat.is24HourFormat(this)).show()
    startButton = picker { timeDialog(start) { end = Share.movedEnd(start, it, end); start = it } }
    endButton = picker { timeDialog(end) { end = it } }
    allDay = SwitchCompat(this).apply {
      this.text = "All day"; textSize = 16f; setTextColor(text); minHeight = dp(48)
      setOnCheckedChangeListener { _, _ -> showWhen() }
    }
    calendarLabel = caption("Calendar")
    calendarPicker = Spinner(this).apply { minimumHeight = dp(48) }
    formError = TextView(this).apply { setTextColor(getColor(R.color.kinwall_share_error)); visibility = View.GONE; setPadding(0, dp(8), 0, 0) }
    return LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
      listOf(caption("Title"), title, dayButton, allDay, startButton, endButton, caption("Place"), place, caption("Notes"), notes, calendarLabel, calendarPicker, formError).forEach(::addView)
    }
  }

  /** Shows these of the buttons and hides the rest. */
  private fun show(vararg views: View) {
    for (v in listOf(eventForm, add, addToCalendar, openInKinwall, notThat, choices, openSaved, done)) v.visibility = if (v in views) View.VISIBLE else View.GONE
  }

  private fun busy(text: String) {
    label.text = text
    spinner.visibility = View.VISIBLE
    show()
  }

  /** "What is this?" with Restaurant, Book and Event; Cancel closes the sheet. */
  private fun showChoices() {
    spinner.visibility = View.GONE
    label.text = "What is this?"
    done.text = "Cancel"
    show(choices, done)
  }

  /** One line and Done. */
  private fun result(text: String) {
    spinner.visibility = View.GONE
    label.text = text
    done.text = "Done"
    show(done)
  }

  companion object {
    private val http = OkHttpClient.Builder().callTimeout(60, TimeUnit.SECONDS).build()
    private class SignInNeeded : Exception()

    /** Sends it to the family's Kinwall with the app's own sign-in: the answer, or one line saying what went wrong. */
    fun post(context: Context, request: Share.Request): Share.Outcome = try {
      val (code, body) = call(context, "api/share", request.json())
      Share.outcome(code, body)
    } catch (e: SignInNeeded) {
      Share.Outcome.Failed(Share.SIGN_IN)
    } catch (e: Exception) {
      Share.Outcome.Failed("Can't reach Kinwall. Check your connection and try again.")
    }

    /** The calendars this phone can add an event to (Share.addable), or null when they can't be read. */
    fun calendars(context: Context): List<Share.FamilyCalendar>? = try {
      call(context, "api/calendars", null).let { (code, body) -> if (code == 200) Share.addable(body) else null }
    } catch (e: Exception) {
      null
    }

    /** GETs (no body) or POSTs JSON to the family's server, signed in: the status and the reply. */
    private fun call(context: Context, path: String, json: String?): Pair<Int, String> {
      val (base, key) = credential(context) ?: throw SignInNeeded()
      val req = Request.Builder().url(base.toHttpUrl().resolve(path)!!).header("Authorization", "Bearer $key")
        .apply { if (json != null) post(json.toRequestBody("application/json".toMediaType())) }.build()
      return http.newCall(req).execute().use { it.code to it.body?.string().orEmpty() }
    }

    /** The server and a key: the app's OAuth access token (src/oauth.ts; refreshed first and saved
     * back if it's about to lapse, since refresh tokens rotate and the app re-reads them before its
     * own refresh, src/session.ts), else a paired device's key (src/sharedKey.ts shareKey). Null
     * when signed out. Never the widgets' everyday key. */
    private fun credential(context: Context): Pair<String, String>? {
      Keychain.get(context, "family.kinwall.oauth")?.let { saved ->
        val t = JSONObject(saved)
        if (t.getDouble("expiresAt") - System.currentTimeMillis() < 5 * 60_000) {
          val form = FormBody.Builder().add("grant_type", "refresh_token").add("refresh_token", t.getString("refreshToken")).add("client_id", t.getString("clientId")).build()
          http.newCall(Request.Builder().url(t.getString("baseURL").toHttpUrl().resolve("oauth/token")!!).post(form).build()).execute().use { res ->
            if (res.code == 400 || res.code == 401) throw SignInNeeded() // the grant is gone (revoked, expired or used)
            if (!res.isSuccessful) throw java.io.IOException("refresh ${res.code}")
            val r = JSONObject(res.body!!.string())
            t.put("accessToken", r.getString("access_token")).put("refreshToken", r.getString("refresh_token"))
              .put("expiresAt", System.currentTimeMillis() + r.getDouble("expires_in") * 1000).put("scope", r.optString("scope"))
            Keychain.set(context, "family.kinwall.oauth", t.toString())
          }
        }
        return t.getString("baseURL") to t.getString("accessToken")
      }
      return Keychain.get(context, "family.kinwall.share")?.let { JSONObject(it) }?.let { it.getString("baseURL") to it.getString("key") }
    }
  }
}
