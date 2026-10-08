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
  /** What a photo or some text is. A link goes without one: the server reads the page. A Maps place
   * is a restaurant or a place (a contact of kind place), picked in "Restaurant or place?". */
  enum class Kind { RECIPE, RESTAURANT, BOOK, EVENT, PLACE; val wire get() = name.lowercase() }

  /** `event` is an event as the person checked it in the sheet (sent instead of text); `save` adds it
   * to `calendarId` now instead of answering with a link to check it. `preview`: a recipe, restaurant
   * or book comes back as what would be saved (Result.preview), and nothing is saved; `token` goes
   * with the save after a link's preview, so Kinwall doesn't read the page again. */
  data class Request(val kind: Kind? = null, val url: String? = null, val text: String? = null, val name: String? = null, val event: EventDraft? = null, val save: Boolean = false, val calendarId: String? = null, val preview: Boolean = false, val token: String? = null) {
    fun json(): String = JSONObject().apply {
      kind?.let { put("kind", it.wire) }
      url?.let { put("url", it) }
      text?.let { put("text", it) }
      name?.let { put("name", it) }
      event?.let { put("event", it.json()) }
      if (save) put("save", true)
      calendarId?.let { put("calendarId", it) }
      if (preview) put("preview", true)
      token?.let { put("token", it) }
    }.toString()

    /** The save after `shown`'s card: the same share without preview, with its token. */
    fun saving(shown: Result) = copy(preview = false, token = shown.preview?.token)
  }

  /** What would be saved (the server's ShareResult preview), for the sheet's card: the photo or
   * cover, the name, short lines of facts, and a line when it's already in Kinwall. */
  data class Preview(val title: String, val imageUrl: String? = null, val lines: List<String> = emptyList(), val already: String? = null, val token: String? = null) {
    companion object {
      private fun JSONObject.text(key: String) = if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
      fun from(json: JSONObject?) = json?.let { p ->
        val lines = p.optJSONArray("lines")
        Preview(p.optString("title"), p.text("imageUrl"), (0 until (lines?.length() ?: 0)).map { lines!!.getString(it) }, p.text("already"), p.text("token"))
      }
    }
  }

  /** The card's title: "Check the recipe", like the event form's "Check the event". */
  fun checkTitle(kind: Kind) = "Check the " + when (kind) { Kind.RECIPE -> "recipe"; Kind.RESTAURANT -> "restaurant"; Kind.BOOK -> "book"; Kind.EVENT -> "event"; Kind.PLACE -> "place" }

  /** An event as Kinwall read it (or as the person changed it): a YYYY-MM-DD date and HH:MM times on
   * the household's clock; no time is all day. */
  data class EventDraft(val title: String? = null, val date: String? = null, val time: String? = null, val end: String? = null, val place: String? = null, val notes: String? = null) {
    fun json() = JSONObject().apply { title?.let { put("title", it) }; date?.let { put("date", it) }; time?.let { put("time", it) }; end?.let { put("end", it) }; place?.let { put("place", it) }; notes?.let { put("notes", it) } }
    companion object {
      private fun JSONObject.text(key: String) = if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
      fun from(json: JSONObject?) = json?.let { EventDraft(it.text("title"), it.text("date"), it.text("time"), it.text("end"), it.text("place"), it.text("notes")) }
    }
  }

  /** `event`: an event to check, what Kinwall read, for the sheet's fields (older servers leave it out).
   * `preview`: with Request.preview, what would be saved (older servers save it and leave this out). */
  data class Result(val kind: Kind, val summary: String, val link: String, val review: Boolean, val event: EventDraft? = null, val preview: Preview? = null) {
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

  /** A new event's end with no end read: `minutes` after the start (HH:MM). */
  fun endAfter(start: String, minutes: Int) = movedEnd("00:00", start, "%02d:%02d".format(minutes / 60, minutes % 60))

  /** How long a new event lasts, from GET api/settings (defaultEventMinutes): an hour on older servers. */
  fun eventMinutes(settings: String) = try { JSONObject(settings).optInt("defaultEventMinutes", 60).takeIf { it > 0 } ?: 60 } catch (e: Exception) { 60 }

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

  /** An Apple or Google Maps place's link (the server's restaurant-import.ts mapsPlace). */
  fun isMapsPlace(url: String): Boolean {
    val u = try { java.net.URI(url) } catch (e: Exception) { return false }
    val host = u.host?.lowercase() ?: return false
    val path = u.path.orEmpty()
    return host == "maps.apple.com" || host == "maps.apple" || host == "maps.app.goo.gl" || (host == "goo.gl" && path.startsWith("/maps"))
      || Regex("^maps\\.google\\.[a-z.]+$").matches(host) || (Regex("^(www\\.)?google\\.[a-z.]+$").matches(host) && path.startsWith("/maps"))
  }

  /** A Maps place in shared text (Google Maps shares "Name\nAddress\nhttps://maps.app.goo.gl/…"): its
   * link, and the first line that isn't a link as its name. Null when the text has no Maps link. */
  fun mapsPlace(text: String): Pair<String, String?>? {
    val link = LINK.findAll(text).map { trimLink(it.value) }.firstOrNull(::isMapsPlace) ?: return null
    return link to text.lines().map { it.trim() }.firstOrNull { it.isNotEmpty() && !LINK.containsMatchIn(it) }
  }

  /** The server's answer as one line: its summary, or what to do about an error without one. */
  fun outcome(status: Int, body: String): Outcome {
    val json = try { JSONObject(body) } catch (e: Exception) { null }
    if (status == 200 && json != null) {
      val kind = Kind.entries.firstOrNull { it.wire == json.optString("kind") }
      val summary = json.optString("summary")
      if (kind != null && summary.isNotEmpty()) return Outcome.Done(Result(kind, summary, json.optString("link"), json.optBoolean("review"), EventDraft.from(json.optJSONObject("event")), Preview.from(json.optJSONObject("preview"))))
    }
    json?.optString("summary")?.takeIf { it.isNotEmpty() }?.let { return Outcome.Failed(it) }
    return Outcome.Failed(when (status) {
      401, 403 -> SIGN_IN // signed out, or a wall screen's or a kid's device
      404 -> "This Kinwall can't take shares yet. Update it, then share again."
      else -> "Couldn't add it to Kinwall: ${json?.optString("error")?.takeIf { it.isNotEmpty() } ?: "error $status"}."
    })
  }

  /** The app's OAuth sign-in (src/oauth.ts Tokens), refreshed when it's within five minutes of
   * lapsing. The app refreshes the same tokens apart from the share sheet (src/tokenRefresh.ts);
   * nothing locks them out of each other, but the server hands the same new pair to the same
   * refresh token sent twice within 30 seconds. `refresh` answers the server's reply, or null when
   * it turned the refresh down: then the saved tokens are read again, since the app may have just
   * rotated them. Null: sign in again. A new pair is saved before use (tried twice; not saved, it
   * still works this once). */
  fun freshTokens(saved: JSONObject, now: Long, reread: () -> JSONObject?, refresh: (JSONObject) -> JSONObject?, save: (JSONObject) -> Boolean): JSONObject? {
    if (saved.getDouble("expiresAt") - now >= 5 * 60_000) return saved
    val r = refresh(saved) ?: return reread()?.takeIf { it.optString("refreshToken") != saved.getString("refreshToken") }
    val t = JSONObject(saved.toString()).put("accessToken", r.getString("access_token")).put("refreshToken", r.getString("refresh_token"))
      .put("expiresAt", now + r.getDouble("expires_in") * 1000).put("scope", r.optString("scope"))
    if (!save(t)) save(t)
    return t
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
      Kind.RECIPE, Kind.PLACE -> {}
    }
    return lines.joinToString("\n")
  }

  /** The words to send for a kind: the header lines first (the server takes the first of each), then
   * the words as read. A menu (without the model) is named by its first line when that's words, not a
   * price (the card shows it before anything is saved), and the lines its name, phone and address
   * came from are left out of the words, so they aren't read as menu items. */
  fun withHeaders(kind: Kind, found: List<Found>, raw: String, zone: TimeZone = TimeZone.getDefault()): String {
    var head = headers(kind, found, zone)
    var lines = raw.trim().lines()
    if (kind == Kind.RESTAURANT) {
      val used = useful(found).filter { it.type == Type.PHONE || it.type == Type.ADDRESS }.flatMap { it.text.lines() }.map { it.trim() }.filter { it.length >= 6 }
      val name = lines.firstOrNull()?.trim()?.takeIf { it.length in 2..60 && it.any(Char::isLetter) && !PRICE.containsMatchIn(it) && used.none(it::contains) }
      if (name != null) head = listOf("Name: $name", head).filter { it.isNotEmpty() }.joinToString("\n")
      lines = lines.drop(if (name != null) 1 else 0).filter { l -> used.none(l::contains) }
    }
    return listOf(head, lines.joinToString("\n").trim()).filter { it.isNotEmpty() }.joinToString("\n\n")
  }

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
      Website: its website, only when the text shows it
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
    Kind.RECIPE, Kind.PLACE -> null
  }
  private const val LEAVE_OUT = "Answer in exactly this format and nothing else, and leave out any line you can't find:"

  /** Rewrites a photo's text into the lines Kinwall reads for a kind the person picked. */
  fun prompt(kind: Kind, text: String): String? {
    val what = when (kind) {
      Kind.RESTAURANT -> "a photo of a restaurant menu"
      Kind.BOOK -> "a photo of a book's cover or back"
      Kind.EVENT -> "a flyer, an invitation or a screenshot"
      Kind.RECIPE, Kind.PLACE -> return null
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

  /** What to send for a menu: the model's name, phone, address and website lines (anything else in
   * its answer is dropped), then "Menu:" and the words as read. The model only reads the top of a
   * menu: rewriting a whole menu took it 25 s and more a page, dropped sections and mixed lines up,
   * while Kinwall reads the words as read well (restaurant-import.ts, menu-text.ts). */
  fun menuText(answer: String?, raw: String): String {
    val header = (answer ?: "").replace("**", "").lines().map { it.trim() }
      .filter { Regex("""^(name|cuisine|phone|address|website)\s*:\s*\S""", RegexOption.IGNORE_CASE).containsMatchIn(it) }
    return if (header.isEmpty()) raw else (header + listOf("Menu:", raw)).joinToString("\n")
  }

  // --- Several photos (a menu over pages) ---------------------------------------------------------

  /** The line between photos' words, which Kinwall skips ("--- Page 2 ---"). */
  fun pageLine(n: Int) = "--- Page $n ---"

  /** Several photos' words (or one) as one text, in the order shared, a page line between them. */
  fun joinPages(pages: List<String>) = pages.map { it.trim() }.filter { it.isNotEmpty() }
    .mapIndexed { i, p -> if (i == 0) p else "${pageLine(i + 1)}\n$p" }.joinToString("\n")

  /** How much text Gemini Nano takes in one go: about 4,000 tokens for the prompt, the words and its
   * answer together, and a menu's answer is about as long as its words. */
  const val PAGE_LIMIT = 4000

  /** The joined words in parts of at most `limit` characters for the model: all of them when they
   * fit, else whole pages together while they fit, and a page over the limit split between lines. */
  fun chunks(pages: List<String>, limit: Int = PAGE_LIMIT): List<String> {
    val joined = joinPages(pages)
    if (joined.length <= limit) return if (joined.isEmpty()) emptyList() else listOf(joined)
    val pieces = mutableListOf<String>()
    pages.map { it.trim() }.filter { it.isNotEmpty() }.forEachIndexed { i, p ->
      val page = if (i == 0) p else "${pageLine(i + 1)}\n$p"
      if (page.length <= limit) { pieces += page; return@forEachIndexed }
      var part = ""
      for (whole in page.split("\n")) {
        var line = whole
        while (line.length > limit) { // one line too long on its own: cut it
          if (part.isNotEmpty()) { pieces += part; part = "" }
          pieces += line.take(limit); line = line.drop(limit)
        }
        part = when { part.isEmpty() -> line; part.length + 1 + line.length <= limit -> "$part\n$line"; else -> { pieces += part; line } }
      }
      if (part.isNotEmpty()) pieces += part
    }
    val out = mutableListOf<String>()
    for (piece in pieces) if (out.isNotEmpty() && out.last().length + 1 + piece.length <= limit) out[out.lastIndex] = out.last() + "\n" + piece else out += piece
    return out
  }

  /** A line's value in the model's answer ("Name: Corner Slice" → "Corner Slice"). */
  private fun value(label: String, text: String) = text.lines().firstNotNullOfOrNull { line ->
    val parts = line.split(':', limit = 2)
    if (parts.size == 2 && parts[0].trim().lowercase() == label) parts[1].trim().takeIf { it.isNotEmpty() } else null
  }

  /** The model's answer to `guessPrompt`: its kind and the lines to send, or null when it's unsure. */
  fun guess(answer: String): Pair<Kind, String>? {
    val lines = answer.replace("**", "").lines().map { it.trim() }.dropWhile { it.isEmpty() }
    val first = lines.firstOrNull() ?: return null
    if (!first.lowercase().startsWith("kind:")) return null
    val kind = Kind.entries.firstOrNull { it.wire == first.drop(5).trim().lowercase() }?.takeIf { it != Kind.RECIPE && it != Kind.PLACE } ?: return null
    val text = lines.drop(1).joinToString("\n").trim()
    return if (text.isEmpty()) null else kind to text
  }

  /** The sheet's one line for a guess: "Looks like an event: Spring fair, Saturday, May 9, 2026", or
   * for several photos of a menu "Looks like a menu: Corner Slice, 3 pages". */
  fun guessLine(kind: Kind, text: String, pages: Int = 1): String {
    fun value(label: String) = value(label, text)?.let { if (it.length > 60) it.take(59) + "…" else it }
    val (what, detail) = when (kind) {
      Kind.EVENT -> "an event" to listOfNotNull(value("title"), value("date")).joinToString(", ").takeIf { it.isNotEmpty() }
      Kind.BOOK -> "a book" to value("title")
      Kind.PLACE -> "a place" to null
      Kind.RESTAURANT, Kind.RECIPE -> "a menu" to listOfNotNull(value("name"), if (pages > 1) "$pages pages" else null).joinToString(", ").takeIf { it.isNotEmpty() }
    }
    return "Looks like $what" + (detail?.let { ": $it" } ?: "")
  }

  /** The small button under a guess: "Not an event?". */
  fun notLabel(kind: Kind) = when (kind) { Kind.EVENT -> "Not an event?"; Kind.BOOK -> "Not a book?"; Kind.PLACE -> "Not a place?"; else -> "Not a menu?" }

  /** An EAN-13 that's an ISBN (978/979), off a back cover's barcode. */
  fun isbnBarcode(value: String?) = value?.takeIf { it.length == 13 && it.all(Char::isDigit) && (it.startsWith("978") || it.startsWith("979")) }

  // --- Reading a photo's words (ShareReader.kt): the same as KinwallKit's Share.swift -------------

  /** A line of text read off a photo and where it is: x and y from the top left, in any unit (ML
   * Kit's pixels), and how far its baseline drops per unit across (a tilted photo). A QR code's
   * payload goes in one too. */
  data class TextLine(val text: String, val x: Double, val y: Double, val width: Double, val height: Double, val slope: Double = 0.0) {
    val maxX get() = x + width
    val maxY get() = y + height
    val midY get() = y + height / 2
  }

  /** A photo's lines as one text, in the order the reader gave them (ML Kit reads a block at a time),
   * put back together where the reader split them, as KinwallKit's Share.swift does:
   * 1. a price read on its own goes on the most level line to its left in the nearest column that
   *    has no price yet, across dot leaders, level along the photo's tilt;
   * 2. the pieces of one row read one after the other go on one line;
   * 3. an item's name over two lines ("Jumbo Chocolate", "Chip Cookie $2.25") is one line: the first
   *    has no price and the second does, same left edge, same size, closer under it than the next
   *    item would be. */
  fun readingOrder(input: List<TextLine>): String {
    val lines = input.filter { it.text.isNotBlank() && it.height > 0 }
    val page = lines.maxOfOrNull { it.maxX } ?: 0.0
    val slopes = lines.filter { it.width > it.height * 4 }.map { it.slope }.sorted()
    val tilt = if (slopes.isEmpty()) 0.0 else slopes[slopes.size / 2]
    fun mid(l: TextLine) = l.midY - tilt * (l.x + l.width / 2)
    val texts = lines.map { it.text }.toMutableList()
    val priced = mutableSetOf<Int>()
    for ((j, p) in lines.withIndex()) {
      if (!isPrice(p.text)) continue
      val level = lines.indices.filter { k ->
        val l = lines[k]
        k != j && k !in priced && !isPrice(l.text) && !hasPrice(l.text) && kotlin.math.abs(mid(l) - mid(p)) < minOf(l.height, p.height) * 0.6 &&
          l.maxX <= p.x + p.height * 0.5 && p.x - l.maxX < page * 0.35 && l.height < p.height * 2 && p.height < l.height * 2 && l.width > l.height
      }
      val near = level.minOfOrNull { p.x - lines[it].maxX } ?: continue
      val t = level.filter { p.x - lines[it].maxX <= near + page * 0.1 }.minByOrNull { kotlin.math.abs(mid(lines[it]) - mid(p)) } ?: continue
      texts[t] = texts[t] + " " + p.text
      texts[j] = ""
      priced += t
    }
    val rows = mutableListOf<Pair<String, TextLine>>()
    for ((j, l) in lines.withIndex()) {
      val text = texts[j]
      if (text.isEmpty()) continue
      val row = rows.lastOrNull()
      val last = row?.second
      if (row != null && last != null && kotlin.math.abs(mid(l) - mid(last)) < minOf(l.height, last.height) * 0.6 && l.x >= last.maxX - l.height * 0.5 &&
        (isPrice(text) || (l.x - last.maxX < l.height * 2 && text.count(Char::isLetter) >= 3))) rows[rows.lastIndex] = "${row.first} $text" to l
      else if (row != null && last != null && !hasPrice(row.first) && hasPrice(text) && nameLike(row.first) && nameLike(text) && kotlin.math.abs(l.x - last.x) < l.height * 0.5 &&
        l.y > last.midY && l.y - last.maxY < l.height * 0.35 && l.height < last.height * 1.33 && last.height < l.height * 1.33) rows[rows.lastIndex] = "${row.first} $text" to l
      else rows += text to l
    }
    return rows.joinToString("\n") { it.first }
  }

  /** Only prices: "$8.30", "(4) $7.25 | (8) $13.50", "$9.35 (Single) | $12.45 (Double)", "+$5.00". */
  fun isPrice(s: String): Boolean {
    val letters = s.count(Char::isLetter)
    return letters <= 14 && letters <= s.count(Char::isDigit) * 2 && hasPrice(s)
  }
  /** A price somewhere in it ("$12.45", "12.45"), never a number run into letters ("+8t"). */
  fun hasPrice(s: String) = Regex("""(\$\s?\d{1,4}([.,]\d\d)?|\d[.,]\d\d)(?![\p{L}\d])""").containsMatchIn(s)
  /** The words of a name: capitalized, no comma. */
  private fun nameLike(s: String) = s.firstOrNull()?.isUpperCase() == true && s.none { it in ",:|;" } && s.split(" ").size <= 5

  /** A photo's lines with the ones a closer look found (the photo read again in parts), each new one
   * after the line closest above it in its column; one that overlaps a line already there is left out. */
  fun merged(base: List<TextLine>, more: List<TextLine>): List<TextLine> {
    val out = base.toMutableList()
    val page = base.maxOfOrNull { it.maxX } ?: 0.0
    fun overlaps(a: TextLine, b: TextLine) = a.x < b.maxX && b.x < a.maxX && a.y < b.maxY && b.y < a.maxY
    for (n in more) {
      if (out.any { overlaps(it, n) }) continue
      val at = out.indices.filter { out[it].midY <= n.midY + n.height * 0.5 && out[it].x < n.maxX && n.x - page * 0.25 < out[it].maxX }.maxByOrNull { out[it].midY }
      if (at != null) out.add(at + 1, n) else out += n
    }
    return out
  }

  /** A menu's QR codes as the lines Kinwall reads (restaurant-import.ts splitMenuHeader), going by the
   * words beside each code: "Order online: …" when they say order, "Menu link: …" for a menu,
   * "Website: …" for a website, "QR code: …" (shown, not saved) when they say nothing clear. Codes
   * that aren't web links, or go to social media, reviews, payment or Wi-Fi, are left out. One line of
   * each kind, the first found. `codes` holds each code's payload and box; `words` the photo's lines. */
  fun linkLines(codes: List<TextLine>, words: List<TextLine>): List<String> {
    val out = mutableMapOf<String, String>()
    for (code in codes) {
      val url = try { java.net.URI(code.text.trim()) } catch (e: Exception) { null } ?: continue
      val host = url.host?.lowercase() ?: continue
      if (url.scheme?.lowercase() !in setOf("http", "https") || SKIPPED_HOSTS.any { host == it || host.endsWith(".$it") }) continue
      val reach = maxOf(code.width, code.height)
      val near = words.filter { w -> maxOf(w.x - code.maxX, code.x - w.maxX, 0.0) <= reach && maxOf(w.y - code.maxY, code.y - w.maxY, 0.0) <= reach }
        .joinToString(" ") { it.text.lowercase() }
      val label = when {
        Regex("""\border|\bdelivery|\bpick ?up""").containsMatchIn(near) -> "Order online"
        Regex("""follow|review|\bpay|wi-?fi|survey|feedback|\blike us|\brate us|app store|download""").containsMatchIn(near) -> null
        Regex("""\bmenu""").containsMatchIn(near) -> "Menu link"
        Regex("""website|\bvisit\b""").containsMatchIn(near) -> "Website"
        else -> "QR code"
      } ?: continue
      out.putIfAbsent(label, "$label: ${code.text.trim()}")
    }
    return listOf("Order online", "Menu link", "Website", "QR code").mapNotNull { out[it] }
  }
  private val SKIPPED_HOSTS = listOf("facebook.com", "fb.com", "instagram.com", "tiktok.com", "twitter.com", "x.com", "youtube.com", "youtu.be", "yelp.com",
    "tripadvisor.com", "linkedin.com", "pinterest.com", "g.page", "wa.me", "venmo.com", "paypal.com", "paypal.me", "cash.app",
    "apps.apple.com", "play.google.com")

  /** A menu's text with its QR code lines first, where Kinwall reads its header lines. */
  fun withLinks(links: List<String>, text: String) = if (links.isEmpty()) text else (links + text).joinToString("\n")
}
