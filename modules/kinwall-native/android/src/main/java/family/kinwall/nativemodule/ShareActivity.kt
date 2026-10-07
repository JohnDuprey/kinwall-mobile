package family.kinwall.nativemodule

import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
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
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/** "Kinwall" in Android's share sheet: sends what's shared to the family's Kinwall (POST api/share,
 * Share.kt) in a small sheet over the app it came from, like the iOS share extension
 * (targets/share). A link goes as it is (Kinwall reads the page). A photo or some text is read on the
 * device (ShareReader.kt): an ISBN barcode goes as a book straight away; otherwise the sheet shows a
 * guess ("Looks like an event: …", from Gemini Nano where the phone has it, else from the dates,
 * places and phone numbers in it) with Add to Kinwall and "Not an event?", or asks "What is this?".
 * Something to check (an event, a book to pick) opens in the app; anything saved shows Kinwall's
 * line and the sheet closes itself. A contact shared as text goes on to MainActivity's contact
 * review (plugins/withKinwallNative.js), as before. */
class ShareActivity : AppCompatActivity() {
  private val scope = MainScope()
  private lateinit var spinner: ProgressBar
  private lateinit var label: TextView
  private lateinit var add: Button
  private lateinit var notThat: Button
  private lateinit var choices: LinearLayout
  private lateinit var done: Button

  private sealed interface Choice { data object Add : Choice; data class Pick(val kind: Share.Kind) : Choice }
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

  /** A photo's words or shared text: a guess to confirm, else "What is this?". */
  private suspend fun sendWords(raw: String) {
    val found = scope.async { ShareReader.entities(raw) }
    val model = ShareReader.ask(Share.guessPrompt(raw))?.let(Share::guess)
    val guess = model ?: Share.guessKind(found.await(), raw)?.let { it to Share.withHeaders(it, found.await(), raw) }
    var kind: Share.Kind
    var text: String? = null
    if (guess != null) {
      spinner.visibility = View.GONE
      label.text = Share.guessLine(guess.first, guess.second)
      notThat.text = Share.notLabel(guess.first)
      show(add, notThat, done)
      when (val c = wait()) {
        Choice.Add -> { kind = guess.first; text = guess.second }
        is Choice.Pick -> { kind = c.kind; if (c.kind == guess.first) text = guess.second }
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
    send(Share.Request(kind = kind, text = text), "Adding to Kinwall…")
  }

  private suspend fun send(request: Share.Request, reading: String) {
    busy(reading)
    when (val o = withContext(Dispatchers.IO) { post(this@ShareActivity, request) }) {
      is Share.Outcome.Failed -> result(o.message)
      is Share.Outcome.Done -> if (o.result.needsReview) {
        // Opens it in the app's web view (src/links.ts routeFor, to=shared).
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Share.appLink(o.result.link))).setPackage(packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
      } else {
        result(o.result.summary)
        delay(2000)
        finish()
      }
    }
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
    show()
    return LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER_HORIZONTAL
      setPadding(dp(24), dp(24), dp(24), dp(16))
      listOf(spinner, label, add, notThat, choices, done).forEach(::addView)
    }
  }

  /** Shows these of the buttons and hides the rest. */
  private fun show(vararg views: View) {
    for (v in listOf(add, notThat, choices, done)) v.visibility = if (v in views) View.VISIBLE else View.GONE
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
      val (base, key) = credential(context) ?: throw SignInNeeded()
      val req = Request.Builder().url(base.toHttpUrl().resolve("api/share")!!)
        .header("Authorization", "Bearer $key")
        .post(request.json().toRequestBody("application/json".toMediaType())).build()
      http.newCall(req).execute().use { Share.outcome(it.code, it.body?.string().orEmpty()) }
    } catch (e: SignInNeeded) {
      Share.Outcome.Failed(Share.SIGN_IN)
    } catch (e: Exception) {
      Share.Outcome.Failed("Can't reach Kinwall. Check your connection and try again.")
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
