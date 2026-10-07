package family.kinwall.nativemodule

import org.json.JSONObject
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** "Add to Kinwall" from Android's share sheet (ShareActivity.kt): what to send to the family's
 * POST /api/share (kinwall's docs/using/share-to-kinwall.md) and what its answer means. The pure
 * rules, tested in src/test (ShareTest.kt); the iOS twin is KinwallKit's Share.swift. */
object Share {
  /** What a photo or some text is. A link goes without one: the server reads the page. */
  enum class Kind { RECIPE, RESTAURANT, BOOK, EVENT; val wire get() = name.lowercase() }

  /** `event` is an event as the person checked it in the sheet (sent instead of text); `save` adds it
   * to `calendarId` now instead of answering with a link to check it. */
  data class Request(val kind: Kind? = null, val url: String? = null, val text: String? = null, val event: EventDraft? = null, val save: Boolean = false, val calendarId: String? = null) {
    fun json(): String = JSONObject().apply {
      kind?.let { put("kind", it.wire) }
      url?.let { put("url", it) }
      text?.let { put("text", it) }
      event?.let { put("event", it.json()) }
      if (save) put("save", true)
      calendarId?.let { put("calendarId", it) }
    }.toString()
  }

  /** An event as Kinwall read it (or as the person changed it): a YYYY-MM-DD date and HH:MM times on
   * the household's clock; no time is all day. */
  data class EventDraft(val title: String? = null, val date: String? = null, val time: String? = null, val end: String? = null, val place: String? = null, val notes: String? = null) {
    fun json() = JSONObject().apply { title?.let { put("title", it) }; date?.let { put("date", it) }; time?.let { put("time", it) }; end?.let { put("end", it) }; place?.let { put("place", it) }; notes?.let { put("notes", it) } }
    companion object {
      private fun JSONObject.text(key: String) = if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
      fun from(json: JSONObject?) = json?.let { EventDraft(it.text("title"), it.text("date"), it.text("time"), it.text("end"), it.text("place"), it.text("notes")) }
    }
  }

  /** `event`: an event to check, what Kinwall read, for the sheet's fields (older servers leave it out). */
  data class Result(val kind: Kind, val summary: String, val link: String, val review: Boolean, val event: EventDraft? = null) {
    /** Nothing saved yet (an event or a book to pick): it's checked in Kinwall. */
    val needsReview get() = review
  }

  /** One of the family's calendars this phone can add an event to (the family's default calendar for new events first). */
  data class FamilyCalendar(val id: String, val name: String)

  /** GET /api/calendars' answer as the calendars this phone can add to, in Kinwall's order: the first
   * is the one the app's event sheet picks for a new event (web Calendar.tsx editableCalendars). */
  fun addable(body: String): List<FamilyCalendar> {
    val all = org.json.JSONArray(body)
    val open = (0 until all.length()).map { all.getJSONObject(it) }
      .filter { it.optBoolean("writable") && it.optBoolean("enabled") && it.optBoolean("canEditEvents", true) }
    return (open.filter { it.optBoolean("default") } + open.filterNot { it.optBoolean("default") }).map { FamilyCalendar(it.getString("id"), it.getString("name")) }
  }

  /** What to send for an event: the model's lines, a "---" line, then the words as read, so Kinwall
   * takes the model's lines first and can fill in what it left out (a street) from the words. */
  fun eventText(lines: String?, raw: String): String {
    val l = lines?.trim()?.takeIf { it.isNotEmpty() } ?: return raw
    return if (l.contains(raw.trim())) l else "$l\n---\n$raw" // withHeaders' lines already end with the words
  }

  /** The end after the start moves from `old` to `new` (HH:MM): the same length, at least 15 minutes. */
  fun movedEnd(old: String, new: String, end: String): String {
    fun mins(hm: String) = hm.substring(0, 2).toInt() * 60 + hm.substring(3, 5).toInt()
    val m = mins(new) + maxOf(mins(end) - mins(old), 15)
    return "%02d:%02d".format((m / 60) % 24, m % 60)
  }

  sealed interface Outcome { data class Done(val result: Result) : Outcome; data class Failed(val message: String) : Outcome }

  const val SIGN_IN = "Open Kinwall and sign in as a grown-up, then share again."

  private val LINK = Regex("https?://[^\\s<>\"]+")
  private fun trimLink(s: String) = s.trimEnd('.', ',', ')', '!', '?', ';', ':', '\'', '"')

  /** A shared link: text that is only a link (what a browser shares), or one link with no more
   * than a title around it ("Lemon chicken https://…", as many apps share a page). Else it's text. */
  fun linkIn(text: String): String? {
    val t = text.trim()
    val links = LINK.findAll(t).map { trimLink(it.value) }.toList()
    if (links.size != 1) return null
    val rest = t.replace(links[0], "").trim()
    return if (rest.length <= 120 && !rest.contains('\n')) links[0] else null
  }

  /** The server's answer as one line: its summary, or what to do about an error without one. */
  fun outcome(status: Int, body: String): Outcome {
    val json = try { JSONObject(body) } catch (e: Exception) { null }
    if (status == 200 && json != null) {
      val kind = Kind.entries.firstOrNull { it.wire == json.optString("kind") }
      val summary = json.optString("summary")
      if (kind != null && summary.isNotEmpty()) return Outcome.Done(Result(kind, summary, json.optString("link"), json.optBoolean("review"), EventDraft.from(json.optJSONObject("event"))))
    }
    json?.optString("summary")?.takeIf { it.isNotEmpty() }?.let { return Outcome.Failed(it) }
    return Outcome.Failed(when (status) {
      401, 403 -> SIGN_IN // signed out, or a wall screen's or a kid's device
      404 -> "This Kinwall can't take shares yet. Update it, then share again."
      else -> "Couldn't add it to Kinwall: ${json?.optString("error")?.takeIf { it.isNotEmpty() } ?: "error $status"}."
    })
  }

  /** The app's own link that opens `link` (a Kinwall address with a #/ route) in the app
   * (src/links.ts routeFor, to=shared). A + in it stays a plus (%2B). */
  fun appLink(link: String) = "family.kinwall.app:/open?to=shared&link=" + URLEncoder.encode(link, "UTF-8")

  // --- What's in a photo's words (ML Kit entity extraction, ShareReader.kt) ------------------------

  enum class Type { DATE_TIME, ADDRESS, PHONE, URL, ISBN }
  /** One thing entity extraction found. For a date-time, `millis` is when and `granularity` how
   * exact (ML Kit's DateTimeEntity: 3 a day, 4 an hour, 5 a minute). */
  data class Found(val type: Type, val text: String, val millis: Long = 0, val granularity: Int = 0)

  private const val DAY = 3
  private const val HOUR = 4
  private val SURE_TIME = Regex("""(?i)\d\s*[ap]\.?\s?m\b|\bnoon\b|\bmidnight\b|\b(1[3-9]|2[0-3]):[0-5]\d""")
  /** What's worth a header line: a phone number has at least 7 digits (a ZIP code reads as one). */
  private fun useful(found: List<Found>) = found.filter { it.type != Type.PHONE || it.text.count(Char::isDigit) >= 7 }
  private fun first(found: List<Found>, type: Type) = useful(found).firstOrNull { it.type == type }?.text?.trim()?.takeIf { it.isNotEmpty() }
  private val TIME_ONLY = Regex("""(?i)^\s*(at\s+)?(\d{1,2}(:\d{2})?\s*([ap]\.?\s?m\.?)?|noon|midnight)(\s*(-|–|to)\s*\d{1,2}(:\d{2})?\s*([ap]\.?\s?m\.?)?)?\s*$""")
  /** The first date-time that names a day ("Sat May 9", "tomorrow at 10"), not just a time ("11am",
   * which ML Kit places today: opening hours aren't an event). */
  private fun day(found: List<Found>) = found.filter { it.type == Type.DATE_TIME && it.granularity >= DAY && !TIME_ONLY.matches(it.text) }
    .let { days -> days.firstOrNull { d -> d.text.any(Char::isDigit) } ?: days.firstOrNull() } // "May 9" over "Saturday", read apart

  /** The header lines Kinwall reads best (share-text.ts and the menu import) for a kind, from what
   * entity extraction found: Date/Time/Place, Phone/Address/Website, or ISBN. Empty when nothing fits. */
  fun headers(kind: Kind, found: List<Found>, zone: TimeZone = TimeZone.getDefault()): String {
    fun fmt(pattern: String, millis: Long) = SimpleDateFormat(pattern, Locale.US).apply { timeZone = zone }.format(millis)
    fun minuteOfDay(millis: Long) = Calendar.getInstance(zone).apply { timeInMillis = millis }.let { it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE) }
    val lines = mutableListOf<String>()
    when (kind) {
      Kind.EVENT -> {
        val start = day(found)
        if (start != null) {
          // No year unless the text has one: ML Kit puts "May 9" in this year even when it's past,
          // and Kinwall takes a date without a year as the next one coming up.
          lines += "Date: ${fmt(if (Regex("\\b\\d{4}\\b").containsMatchIn(start.text)) "MMMM d, yyyy" else "MMMM d", start.millis)}"
          // Its time, or the first time on its own ("May 9" then "10 AM"); the next later time is when it ends ("10 AM - 2 PM").
          // Only a time that says AM or PM (or a 24-hour one): ML Kit takes a bare "3:00" as 3 AM, so
          // without one the Time line is left out and Kinwall reads "3:00 - 5:00pm" from the words.
          val times = found.filter { it.type == Type.DATE_TIME && it.granularity >= HOUR && SURE_TIME.containsMatchIn(it.text) }
          val at = if (start.granularity >= HOUR) start.takeIf { SURE_TIME.containsMatchIn(it.text) } else times.firstOrNull()
          if (at != null) {
            val end = times.firstOrNull { it !== at && minuteOfDay(it.millis) > minuteOfDay(at.millis) }
            lines += "Time: ${fmt("h:mm a", at.millis)}" + (end?.let { " - ${fmt("h:mm a", it.millis)}" } ?: "")
          }
        }
        first(found, Type.ADDRESS)?.let { lines += "Place: $it" }
      }
      Kind.RESTAURANT -> {
        first(found, Type.PHONE)?.let { lines += "Phone: $it" }
        first(found, Type.ADDRESS)?.let { lines += "Address: $it" }
        first(found, Type.URL)?.let { lines += "Website: $it" }
      }
      Kind.BOOK -> first(found, Type.ISBN)?.let { lines += "ISBN: $it" }
      Kind.RECIPE -> {}
    }
    return lines.joinToString("\n")
  }

  /** The words to send for a kind: the header lines first (the server takes the first of each), then the words as read. */
  fun withHeaders(kind: Kind, found: List<Found>, raw: String, zone: TimeZone = TimeZone.getDefault()) =
    listOf(headers(kind, found, zone), raw.trim()).filter { it.isNotEmpty() }.joinToString("\n\n")

  private val PRICE = Regex("""(?<![\d.])\$?\d{1,3}\.\d{2}(?![\d])""")
  /** Without the model, what the found things say it is; null when they don't make it clear
   * (the sheet asks "What is this?"). A day and no phone number is an event; prices or a phone
   * number with an address or website (and no day) is a menu; an ISBN is a book. */
  fun guessKind(found: List<Found>, raw: String): Kind? {
    val has = { t: Type -> found.any { it.type == t } }
    val phone = useful(found).any { it.type == Type.PHONE }
    val day = day(found) != null
    return when {
      has(Type.ISBN) -> Kind.BOOK
      PRICE.findAll(raw).count() >= 3 && !day -> Kind.RESTAURANT
      day && !phone -> Kind.EVENT
      phone && !day && (has(Type.ADDRESS) || has(Type.URL)) -> Kind.RESTAURANT
      else -> null
    }
  }

  // --- Gemini Nano (ShareReader.kt): the same prompts as the iOS model step -------------------------

  private fun format(kind: Kind): String? = when (kind) {
    Kind.RESTAURANT -> """
      Name: the restaurant's name
      Cuisine: the kind of food, like Pizza or Thai
      Phone: its phone number
      Address: its address on one line
      Website: its website
      Menu:
      then each menu section's name on its own line, with each of its items on its own line below it as the item's name and then its price, like "Large cheese 14.99"
      """.trimIndent()
    Kind.BOOK -> """
      ISBN: the ISBN, from the barcode's number
      Title: the book's title
      Author: its author
      """.trimIndent()
    Kind.EVENT -> """
      Title: a short name for the event
      Date: its date, like Saturday, May 9, 2026
      Time: its start and end time, like 10:00 AM - 2:00 PM
      Place: the venue's name and its full street address and town on one line, like The Rivers Residence, 12 Elm Road, Springfield
      Notes: anything else worth knowing, like what to bring, costs, or how to RSVP
      """.trimIndent()
    Kind.RECIPE -> null
  }
  private const val LEAVE_OUT = "Answer in exactly this format and nothing else, and leave out any line you can't find:"

  /** Rewrites a photo's text into the lines Kinwall reads for a kind the person picked. */
  fun prompt(kind: Kind, text: String): String? {
    val what = when (kind) {
      Kind.RESTAURANT -> "a photo of a restaurant menu"
      Kind.BOOK -> "a photo of a book's cover or back"
      Kind.EVENT -> "a flyer, an invitation or a screenshot"
      Kind.RECIPE -> return null
    }
    return format(kind)?.let { "This is text from $what. $LEAVE_OUT\n$it\n\n${text.take(6000)}" }
  }

  /** Says what the text is and rewrites it in the same answer (`guess`). */
  fun guessPrompt(text: String) = """
    |This is text from a photo or a share. Decide whether it is a restaurant's menu, a book (its cover or back), or an event (a flyer, an invitation or a screenshot with a date). On the first line write "Kind: restaurant", "Kind: book" or "Kind: event", or "Kind: unsure" when it's none of these or you can't tell. Then, for that kind, ${LEAVE_OUT.replaceFirstChar { it.lowercase() }}
    |
    |For a restaurant:
    |${format(Kind.RESTAURANT)}
    |
    |For a book:
    |${format(Kind.BOOK)}
    |
    |For an event:
    |${format(Kind.EVENT)}
    |
    |${text.take(6000)}
    """.trimMargin()

  /** The model's answer to `guessPrompt`: its kind and the lines to send, or null when it's unsure. */
  fun guess(answer: String): Pair<Kind, String>? {
    val lines = answer.replace("**", "").lines().map { it.trim() }.dropWhile { it.isEmpty() }
    val first = lines.firstOrNull() ?: return null
    if (!first.lowercase().startsWith("kind:")) return null
    val kind = Kind.entries.firstOrNull { it.wire == first.drop(5).trim().lowercase() }?.takeIf { it != Kind.RECIPE } ?: return null
    val text = lines.drop(1).joinToString("\n").trim()
    return if (text.isEmpty()) null else kind to text
  }

  /** The sheet's one line for a guess: "Looks like an event: Spring fair, Saturday, May 9, 2026". */
  fun guessLine(kind: Kind, text: String): String {
    fun value(label: String) = text.lines().firstNotNullOfOrNull { line ->
      val parts = line.split(':', limit = 2)
      if (parts.size == 2 && parts[0].trim().lowercase() == label) parts[1].trim().takeIf { it.isNotEmpty() } else null
    }
    val (what, detail) = when (kind) {
      Kind.EVENT -> "an event" to listOfNotNull(value("title"), value("date")).joinToString(", ").takeIf { it.isNotEmpty() }
      Kind.BOOK -> "a book" to value("title")
      Kind.RESTAURANT, Kind.RECIPE -> "a menu" to value("name")
    }
    return "Looks like $what" + (detail?.let { ": " + if (it.length > 60) it.take(59) + "…" else it } ?: "")
  }

  /** The small button under a guess: "Not an event?". */
  fun notLabel(kind: Kind) = when (kind) { Kind.EVENT -> "Not an event?"; Kind.BOOK -> "Not a book?"; else -> "Not a menu?" }

  /** An EAN-13 that's an ISBN (978/979), off a back cover's barcode. */
  fun isbnBarcode(value: String?) = value?.takeIf { it.length == 13 && it.all(Char::isDigit) && (it.startsWith("978") || it.startsWith("979")) }
}
