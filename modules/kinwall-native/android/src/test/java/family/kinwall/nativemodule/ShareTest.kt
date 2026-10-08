package family.kinwall.nativemodule

import family.kinwall.nativemodule.Share.Found
import family.kinwall.nativemodule.Share.Kind
import family.kinwall.nativemodule.Share.Type
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.TimeZone

// The share sheet's pure rules (Share.kt). Run after a prebuild: cd android && ./gradlew :kinwall-native:testReleaseUnitTest
class ShareTest {
  private val ny = TimeZone.getTimeZone("America/New_York")
  // Saturday, May 9, 2026 10:00 AM and 2:00 PM in New York (EDT, UTC-4).
  private val tenAm = 1778335200000L
  private val twoPm = tenAm + 4 * 3_600_000

  @Test fun linkIn() {
    assertEquals("https://example.org/tacos", Share.linkIn("  https://example.org/tacos\n"))
    assertEquals("https://example.org/tacos", Share.linkIn("Lemon chicken https://example.org/tacos."))
    assertNull("a flyer that mentions a site is words", Share.linkIn("Spring fair\nSaturday May 9\nMore at https://school.example"))
    assertNull(Share.linkIn("two https://a.example and https://b.example"))
    assertNull(Share.linkIn("no link here"))
  }

  @Test fun mapsPlaces() {
    for (maps in listOf("https://maps.app.goo.gl/AbCd", "https://goo.gl/maps/AbCd", "https://www.google.com/maps/place/Maple+Park", "https://maps.google.co.uk/?q=Maple+Park", "https://maps.apple.com/place?name=Maple%20Park")) assertTrue(maps, Share.isMapsPlace(maps))
    for (not in listOf("https://www.google.com/search?q=maps", "https://goo.gl/AbCd", "https://notgoogle.com/maps", "not a link")) assertFalse(not, Share.isMapsPlace(not))
    assertEquals("https://maps.app.goo.gl/AbCd" to "Maple Park", Share.mapsPlace("Maple Park\n20 Lake Rd, Springfield\nhttps://maps.app.goo.gl/AbCd"))
    assertEquals("https://maps.app.goo.gl/AbCd" to null, Share.mapsPlace("https://maps.app.goo.gl/AbCd"))
    assertNull(Share.mapsPlace("Party! https://example.org/rsvp"))
    val json = JSONObject(Share.Request(Kind.PLACE, "https://maps.app.goo.gl/AbCd", name = "Maple Park").json())
    assertEquals(listOf("place", "https://maps.app.goo.gl/AbCd", "Maple Park"), listOf(json.getString("kind"), json.getString("url"), json.getString("name")))
  }

  @Test fun eventHeaders() {
    val found = listOf(Found(Type.DATE_TIME, "Saturday May 9 10am", tenAm, 5), Found(Type.DATE_TIME, "2pm", twoPm, 4), Found(Type.ADDRESS, "12 Elm St, Springfield"))
    assertEquals("Date: May 9\nTime: 10:00 AM - 2:00 PM\nPlace: 12 Elm St, Springfield", Share.headers(Kind.EVENT, found, ny))
    assertEquals("a day, then its times", "Date: May 9\nTime: 10:00 AM - 2:00 PM",
      Share.headers(Kind.EVENT, listOf(Found(Type.DATE_TIME, "May 9", tenAm, 3), Found(Type.DATE_TIME, "10am", tenAm, 4), Found(Type.DATE_TIME, "2 pm", twoPm, 4)), ny))
    assertEquals("times alone aren't a day", "", Share.headers(Kind.EVENT, listOf(Found(Type.DATE_TIME, "10:00 AM - 2:00 PM", tenAm, 5)), ny))
    assertEquals("a day without a time; a year only when it's written", "Date: May 9, 2026", Share.headers(Kind.EVENT, listOf(Found(Type.DATE_TIME, "May 9, 2026", tenAm, 3)), ny))
    // What ML Kit made of the demo flyer: "Saturday" and "May 9 10 AM" apart, and its ZIP code as a phone number.
    val flyer = listOf(Found(Type.DATE_TIME, "Saturday", twoPm + 154 * 86_400_000L, 3), Found(Type.DATE_TIME, "May 9\n10 AM", tenAm, 4), Found(Type.DATE_TIME, "2 PM", twoPm, 4),
      Found(Type.ADDRESS, "12 Elm Street, Springfield, IL 62701"), Found(Type.PHONE, "62701"))
    assertEquals("Date: May 9\nTime: 10:00 AM - 2:00 PM\nPlace: 12 Elm Street, Springfield, IL 62701", Share.headers(Kind.EVENT, flyer, ny))
    assertEquals(Kind.EVENT, Share.guessKind(flyer, "Spring Fair"))
    // The made-up invite: "Saturday, October 24th 3:00 - 5:00pm" came back as one date-time at 3 AM (here on May 9).
    // A time with no AM or PM is left out, for Kinwall to read the range from the words.
    val bare = listOf(Found(Type.DATE_TIME, "Saturday, May 9th 3:00", tenAm, 5), Found(Type.ADDRESS, "12 Elm Road, Springfield"))
    assertEquals("Date: May 9\nPlace: 12 Elm Road, Springfield", Share.headers(Kind.EVENT, bare, ny))
    assertEquals("a bare end isn't taken either", "Date: May 9\nTime: 10:00 AM",
      Share.headers(Kind.EVENT, listOf(Found(Type.DATE_TIME, "May 9 10am", tenAm, 5), Found(Type.DATE_TIME, "2:00", twoPm, 5)), ny))
    assertEquals("a month alone isn't a date", "", Share.headers(Kind.EVENT, listOf(Found(Type.DATE_TIME, "May", tenAm, 1)), ny))
    assertEquals("Date: May 9\n\nSpring fair\nMay 9", Share.withHeaders(Kind.EVENT, listOf(Found(Type.DATE_TIME, "May 9", tenAm, 3)), " Spring fair\nMay 9 ", ny))
  }

  @Test fun restaurantAndBookHeaders() {
    val found = listOf(Found(Type.PHONE, "(555) 010-1234"), Found(Type.ADDRESS, "1 Main St"), Found(Type.URL, "joespizza.example"), Found(Type.ISBN, "978-0-306-40615-7"))
    assertEquals("Phone: (555) 010-1234\nAddress: 1 Main St\nWebsite: joespizza.example", Share.headers(Kind.RESTAURANT, found))
    assertEquals("ISBN: 978-0-306-40615-7", Share.headers(Kind.BOOK, found))
    assertEquals("Joe's menu", Share.withHeaders(Kind.BOOK, emptyList(), "Joe's menu"))
  }

  @Test fun aMenuWithoutTheModelIsNamedByItsFirstLine() {
    // The made-up menu photo as ML Kit read it: the name on top, then a line with the phone and the address.
    val words = "Juniper Hill Kitchen\nComfort food · (555) 014-2290\n42 Orchard Lane, Springfield\nStarters\nTomato soup 6.50"
    val found = listOf(Found(Type.PHONE, "(555) 014-2290"), Found(Type.ADDRESS, "42 Orchard Lane,\nSpringfield"))
    assertEquals("the lines the header came from aren't menu items",
      "Name: Juniper Hill Kitchen\nPhone: (555) 014-2290\nAddress: 42 Orchard Lane,\nSpringfield\n\nStarters\nTomato soup 6.50", Share.withHeaders(Kind.RESTAURANT, found, words))
    assertEquals("a first line with a price isn't a name", "Pizza 12.99\nSalad 8.00", Share.withHeaders(Kind.RESTAURANT, emptyList(), "Pizza 12.99\nSalad 8.00"))
  }

  @Test fun guessKind() {
    val day = Found(Type.DATE_TIME, "May 9", tenAm, 3)
    val phone = Found(Type.PHONE, "555-555-0100")
    assertEquals(Kind.BOOK, Share.guessKind(listOf(Found(Type.ISBN, "9780306406157"), day), ""))
    assertEquals(Kind.EVENT, Share.guessKind(listOf(day, Found(Type.ADDRESS, "Lincoln School")), "Spring fair"))
    assertNull("a day and a phone number: unclear", Share.guessKind(listOf(day, phone), "RSVP"))
    assertEquals(Kind.RESTAURANT, Share.guessKind(listOf(phone, Found(Type.ADDRESS, "1 Main St")), "Joe's"))
    assertEquals(Kind.RESTAURANT, Share.guessKind(emptyList(), "Cheese 12.99\nPepperoni 14.99\nGarlic knots \$6.50"))
    assertNull("opening hours aren't a day", Share.guessKind(listOf(Found(Type.DATE_TIME, "11am", tenAm, 4)), "Open 11am"))
    assertNull(Share.guessKind(emptyList(), "just some words"))
  }

  @Test fun modelAnswers() {
    assertEquals(Kind.EVENT to "Title: Spring fair\nDate: Saturday, May 9", Share.guess("\n**Kind: Event**\nTitle: Spring fair\nDate: Saturday, May 9\n"))
    assertNull(Share.guess("Kind: unsure"))
    assertNull(Share.guess("Kind: recipe\nTitle: x"))
    assertNull(Share.guess("Kind: book"))
    assertNull(Share.guess("Here you go"))
    assertEquals(true, Share.guessPrompt("FLYER").endsWith("\n\nFLYER"))
    assertEquals(true, Share.prompt(Kind.BOOK, "WOOL")!!.startsWith("This is text from a photo of a book's cover or back. Answer in exactly"))
    assertNull(Share.prompt(Kind.RECIPE, "x"))
  }

  @Test fun guessLines() {
    assertEquals("Looks like an event: Spring fair, Saturday, May 9", Share.guessLine(Kind.EVENT, "Title: Spring fair\nDate: Saturday, May 9"))
    assertEquals("Looks like a menu: Joe's", Share.guessLine(Kind.RESTAURANT, "Name: Joe's\nPhone: 555"))
    assertEquals("Looks like a book", Share.guessLine(Kind.BOOK, "ISBN: 9780306406157"))
    assertEquals("Looks like an event: " + "x".repeat(59) + "…", Share.guessLine(Kind.EVENT, "Title: " + "x".repeat(70)))
    assertEquals("Not an event?", Share.notLabel(Kind.EVENT))
    assertEquals("Not a menu?", Share.notLabel(Kind.RESTAURANT))
  }

  @Test fun isbnBarcode() {
    assertEquals("9780306406157", Share.isbnBarcode("9780306406157"))
    assertNull("a grocery barcode", Share.isbnBarcode("0012345678905"))
    assertNull(Share.isbnBarcode(null))
  }

  @Test fun requestAndOutcome() {
    val book = JSONObject(Share.Request(kind = Kind.BOOK, text = "9780306406157").json())
    assertEquals(listOf("book", "9780306406157", false), listOf(book.getString("kind"), book.getString("text"), book.has("url")))
    val link = JSONObject(Share.Request(url = "https://example.org").json())
    assertEquals(listOf("https://example.org", false), listOf(link.getString("url"), link.has("kind")))
    val ok = Share.outcome(200, """{"kind":"event","summary":"Check the event: Spring fair","link":"https://k.example/#/calendar?draft=event","review":true}""")
    assertEquals(Share.Outcome.Done(Share.Result(Kind.EVENT, "Check the event: Spring fair", "https://k.example/#/calendar?draft=event", true)), ok)
    assertEquals(true, (ok as Share.Outcome.Done).result.needsReview)
    assertEquals(false, Share.Result(Kind.RECIPE, "Imported Tacos", "https://k.example/#/meals", false).needsReview)
    assertEquals(Share.Outcome.Failed("Meals is turned off in Settings → Features"), Share.outcome(403, """{"error":"x","summary":"Meals is turned off in Settings → Features"}"""))
    assertEquals(Share.Outcome.Failed(Share.SIGN_IN), Share.outcome(401, """{"error":"unauthorized"}"""))
    assertEquals(Share.Outcome.Failed(Share.SIGN_IN), Share.outcome(403, "<html>"))
    assertEquals(Share.Outcome.Failed("This Kinwall can't take shares yet. Update it, then share again."), Share.outcome(404, "Not Found"))
    assertEquals(Share.Outcome.Failed("Couldn't add it to Kinwall: error 500."), Share.outcome(500, ""))
  }

  @Test fun appLink() {
    // src/links.ts routeFor (test/links.test.ts) reads it back with URLSearchParams: + stays a plus.
    assertEquals("family.kinwall.app:/open?to=shared&link=https%3A%2F%2Fk.example%2F%23%2Fcalendar%3Fdraft%3Devent%26title%3DSpring%2Bfair",
      Share.appLink("https://k.example/#/calendar?draft=event&title=Spring+fair"))
  }

  @Test fun anEventToCheckAndSaving() {
    val read = Share.outcome(200, """{"kind":"event","summary":"Check the event: Spring fair","link":"https://k.example/#/calendar?draft=event","review":true,"event":{"title":"Spring fair","date":"2026-05-09","time":"10:00","end":null,"place":null}}""")
    assertEquals(Share.EventDraft("Spring fair", "2026-05-09", "10:00"), (read as Share.Outcome.Done).result.event)
    val saved = Share.outcome(200, """{"kind":"event","summary":"Added Spring fair to Family, Sat May 9","link":"https://k.example/#/calendar?event=e1","review":false}""")
    assertEquals(false, (saved as Share.Outcome.Done).result.needsReview)
    assertNull(saved.result.event)
    val body = JSONObject(Share.Request(kind = Kind.EVENT, event = Share.EventDraft("Swim", "2026-05-09"), save = true, calendarId = "c1").json())
    assertEquals(setOf("kind", "event", "save", "calendarId"), body.keys().asSequence().toSet())
    assertEquals(Share.EventDraft("Swim", "2026-05-09"), Share.EventDraft.from(body.getJSONObject("event")))
    assertEquals("Bring a towel", Share.EventDraft.from(Share.EventDraft("Swim", notes = "Bring a towel").json())!!.notes)
    assertEquals(setOf("title", "date"), body.getJSONObject("event").keys().asSequence().toSet())
    assertEquals(false, JSONObject(Share.Request(kind = Kind.EVENT, text = "x").json()).has("save"))
  }

  @Test fun eventTextAndCalendars() {
    assertEquals("Title: Swim\nPlace: Oak Pool\n---\nSWIM\n9 Lake Ave", Share.eventText("Title: Swim\nPlace: Oak Pool", "SWIM\n9 Lake Ave"))
    assertEquals("SWIM", Share.eventText(null, "SWIM"))
    assertEquals("no model: the words once", "SWIM", Share.eventText(" SWIM\n", "SWIM"))
    assertEquals("found lines with the words", "Date: May 9\n\nSWIM", Share.eventText("Date: May 9\n\nSWIM", "SWIM"))
    val cals = """[{"id":"a","name":"Family","writable":true,"enabled":true,"canEditEvents":true},{"id":"b","name":"School","writable":false,"enabled":true},
      {"id":"c","name":"Old","writable":true,"enabled":false},{"id":"d","name":"Work","writable":true,"enabled":true,"canEditEvents":false},{"id":"e","name":"Kids","writable":true,"enabled":true}]"""
    assertEquals(listOf(Share.FamilyCalendar("a", "Family"), Share.FamilyCalendar("e", "Kids")), Share.addable(cals))
    // The family's default calendar for new events comes first.
    assertEquals(listOf("e", "a"), Share.addable(cals.replace("\"name\":\"Kids\",", "\"name\":\"Kids\",\"default\":true,")).map { it.id })
    assertEquals("16:00", Share.movedEnd("10:00", "14:00", "12:00"))
    assertEquals("at least 15 minutes", "09:15", Share.movedEnd("10:00", "09:00", "09:30"))
    assertEquals("00:30", Share.movedEnd("22:00", "23:00", "23:30"))
    assertEquals("10:30", Share.endAfter("09:00", 90))
    assertEquals("past midnight", "02:00", Share.endAfter("23:00", 180))
    assertEquals(45, Share.eventMinutes("{\"defaultEventMinutes\":45}"))
    assertEquals("an older server", 60, Share.eventMinutes("{\"familyName\":\"F\"}"))
    assertEquals(true, Share.prompt(Kind.EVENT, "f")!!.contains("Place: the venue's name and its full street address and town on one line, like The Rivers Residence, 12 Elm Road, Springfield\nNotes: anything else worth knowing, like what to bring, costs, or how to RSVP"))
  }

  // Several photos of one menu, as on iOS (KinwallKit ShareTests).
  @Test fun photosAreJoinedWithPageLines() {
    assertEquals("Pizza\nCheese 12\n--- Page 2 ---\nSides\nFries 3", Share.joinPages(listOf("Pizza\nCheese 12", "  ", "Sides\nFries 3\n")))
    assertEquals("Only one", Share.joinPages(listOf("Only one\n")))
    assertEquals("", Share.joinPages(emptyList()))
  }

  @Test fun aLongMenuIsChunkedByPageThenByLine() {
    val short = listOf("Name: Corner Slice\nPizza\nCheese 12", "Sides\nFries 3")
    assertEquals("short enough: one go", listOf(Share.joinPages(short)), Share.chunks(short, 100))
    val page = (1..30).joinToString("\n") { "Item $it 9.99" }
    val parts = Share.chunks(listOf(page, page, page), 900)
    assertEquals("two pages fit, then the third", 2, parts.size)
    assert(parts.all { it.length <= 900 })
    assert(parts[1].startsWith("--- Page 3 ---"))
    val long = Share.chunks(listOf(page), 150)
    assert(long.all { it.length <= 150 })
    assertEquals("nothing is lost", page, long.joinToString("\n"))
  }

  @Test fun aMenuIsTheModelsHeaderLinesOverTheWordsAsRead() {
    // The same prompt as KinwallKit's Share.swift: a menu's header lines only.
    assert(Share.prompt(Kind.RESTAURANT, "m")!!.endsWith("Website: its website, only when the text shows it\n\nm"))
    val raw = "Pizza\nCheese 12\n--- Page 2 ---\nSides\nFries 3"
    assertEquals("the model's own menu lines are dropped", "Name: Corner Slice\nPhone: 555-0100\nWebsite: none\nMenu:\n$raw",
      Share.menuText("Name: Corner Slice\n**Phone:** 555-0100\nMenu:\nPizza\nCheese 12.00\nWebsite: none\nCuisine:", raw))
    assertEquals(raw, Share.menuText(null, raw))
    assertEquals(raw, Share.menuText("Here you go", raw))
  }

  private fun line(text: String, x: Double, y: Double, w: Double = 0.2, h: Double = 0.02, slope: Double = 0.0) = Share.TextLine(text, x, y, w, h, slope)

  @Test fun aRowsPiecesGoOnOneLineInTheReadersOrder() {
    val lines = listOf(line("Starters", 0.1, 0.1), line("Garlic Knots", 0.1, 0.13), line("(6) $5.10 | (12) $9.20", 0.6, 0.131),
      line("Fresh garlic, butter,", 0.1, 0.16, w = 0.15), line("parsley", 0.27, 0.161, w = 0.05),
      line("Pretzel Bites", 0.1, 0.19), line("$7.25", 0.33, 0.25),
      line("Desserts", 0.7, 0.1), line("0662-259-+8t", 0.82, 0.1, w = 0.05))
    assertEquals("Starters\nGarlic Knots (6) $5.10 | (12) $9.20\nFresh garlic, butter, parsley\nPretzel Bites\n$7.25\nDesserts\n0662-259-+8t", Share.readingOrder(lines))
    assertEquals("Garden Party\nFig & Goat", Share.readingOrder(listOf(line("Garden Party", 0.1, 0.5), line("Fig & Goat", 0.6, 0.5))))
    assertEquals("", Share.readingOrder(emptyList()))
  }

  @Test fun pricesReadAfterTheirNamesGoBackOnTheirRows() {
    val kids = listOf(line("Kids Menu", 0.54, 0.40, h = 0.03), line("Chicken Fingers. $6.25", 0.54, 0.44, w = 0.13), line("Mac & Cheese .", 0.54, 0.47, w = 0.08),
      line("Grilled Cheese", 0.54, 0.50, w = 0.08), line("$6.25", 0.66, 0.471, w = 0.04), line("$6.25", 0.66, 0.502, w = 0.04),
      line("0555-019-+8t", 0.70, 0.49, w = 0.01, h = 0.06))
    assertEquals("Kids Menu\nChicken Fingers. $6.25\nMac & Cheese . $6.25\nGrilled Cheese $6.25\n0555-019-+8t", Share.readingOrder(kids))
    assertEquals("Brownie Sundae $4.25", Share.readingOrder(listOf(line("Brownie Sundae", 0.1, 0.30), line("$4.25", 0.7, 0.308, w = 0.05))))
    val tilted = listOf(line("Fountain Soda and Lemonade, refills free", 0.1, 0.20, w = 0.6, h = 0.04, slope = 0.045), line("Pretzel Bites", 0.1, 0.30, w = 0.1, slope = 0.045),
      line("$7.25", 0.4, 0.312, w = 0.04, slope = 0.045), line("Loaded Tots", 0.1, 0.32, w = 0.1, slope = 0.045), line("$8.30", 0.4, 0.332, w = 0.04, slope = 0.045))
    assertEquals("Fountain Soda and Lemonade, refills free\nPretzel Bites $7.25\nLoaded Tots $8.30", Share.readingOrder(tilted))
    assertEquals("Brownie Sundae\n$4.25", Share.readingOrder(listOf(line("Brownie Sundae", 0.1, 0.30), line("$4.25", 0.7, 0.33, w = 0.05))))
  }

  @Test fun aNameOverTwoLinesIsOneLine() {
    val sweets = listOf(line("Desserts", 0.54, 0.25, h = 0.03), line("Giant Oatmeal", 0.54, 0.29, w = 0.1), line("Raisin Cookie", 0.54, 0.312, w = 0.1), line("$2.25", 0.66, 0.312, w = 0.04),
      line("Fountain", 0.54, 0.40, w = 0.1), line("Soda Products", 0.54, 0.422, w = 0.1), line("$2.85", 0.66, 0.422, w = 0.04),
      line("Water", 0.54, 0.45, w = 0.1), line("$2.85", 0.66, 0.45, w = 0.04))
    assertEquals("Desserts\nGiant Oatmeal Raisin Cookie $2.25\nFountain Soda Products $2.85\nWater $2.85", Share.readingOrder(sweets))
    assertEquals("Nashville Crispy\nFried chicken, slaw $13.50", Share.readingOrder(listOf(line("Nashville Crispy", 0.1, 0.1), line("Fried chicken, slaw $13.50", 0.1, 0.122))))
    assertEquals("Mac & Cheese $6.25\nGrilled Cheese $6.25", Share.readingOrder(listOf(line("Mac & Cheese $6.25", 0.1, 0.1), line("Grilled Cheese $6.25", 0.1, 0.122))))
    assertEquals("Kids Menu\nChicken Fingers $6.25", Share.readingOrder(listOf(line("Kids Menu", 0.1, 0.06, h = 0.035), line("Chicken Fingers $6.25", 0.1, 0.1))))
  }

  @Test fun aCloserLookAddsWhatTheWholePhotoMissed() {
    val base = listOf(line("Desserts", 0.5, 0.2), line("Brownie Sundae", 0.5, 0.25), line("Beverages", 0.5, 0.4), line("Water", 0.5, 0.45))
    val more = listOf(line("Brownie Sundae", 0.5, 0.251), line("$4.25", 0.7, 0.25, w = 0.05), line("$2.85", 0.7, 0.45, w = 0.05))
    assertEquals(listOf("Desserts", "Brownie Sundae", "$4.25", "Beverages", "Water", "$2.85"), Share.merged(base, more).map { it.text })
    assertEquals("Desserts\nBrownie Sundae $4.25\nBeverages\nWater $2.85", Share.readingOrder(Share.merged(base, more)))
  }

  @Test fun aMenusQRCodeGoesByTheWordsBesideIt() {
    val code = line("https://order.cornerslice.example/start", 0.6, 0.7, w = 0.12, h = 0.1)
    val order = listOf(line("Scan To Order Online!", 0.6, 0.82))
    assertEquals(listOf("Order online: https://order.cornerslice.example/start"), Share.linkLines(listOf(code), order))
    assertEquals(listOf("Menu link: https://order.cornerslice.example/start"), Share.linkLines(listOf(code), listOf(line("See our full menu", 0.45, 0.72, w = 0.14))))
    assertEquals(listOf("Website: https://order.cornerslice.example/start"), Share.linkLines(listOf(code), listOf(line("Visit our website", 0.75, 0.7))))
    assertEquals("nothing clear beside it", listOf("QR code: https://order.cornerslice.example/start"), Share.linkLines(listOf(code), listOf(line("Corner Slice", 0.6, 0.65), line("Order online", 0.1, 0.1))))
    assertEquals(emptyList<String>(), Share.linkLines(listOf(code), listOf(line("Leave us a review!", 0.6, 0.82))))
    assertEquals(emptyList<String>(), Share.linkLines(listOf(line("https://www.instagram.com/cornerslice", 0.6, 0.7, 0.1, 0.1)), order))
    assertEquals(emptyList<String>(), Share.linkLines(listOf(line("WIFI:S:Corner;T:WPA;P:secret;;", 0.6, 0.7, 0.1, 0.1)), order))
    assertEquals("no QR code: nothing", emptyList<String>(), Share.linkLines(emptyList(), order))
    val menu = line("https://cornerslice.example/menu.pdf", 0.1, 0.1, 0.1, 0.1)
    assertEquals(listOf("Order online: https://order.cornerslice.example/start", "Menu link: https://cornerslice.example/menu.pdf"),
      Share.linkLines(listOf(menu, code, code), order + line("Our menu", 0.1, 0.22)))
    assertEquals("Order online: https://x.example\nPizza\nCheese 12", Share.withLinks(listOf("Order online: https://x.example"), "Pizza\nCheese 12"))
    assertEquals("Pizza", Share.withLinks(emptyList(), "Pizza"))
  }

  @Test fun guessLineCountsPages() {
    assertEquals("Looks like a menu: Corner Slice, 3 pages", Share.guessLine(Kind.RESTAURANT, "Name: Corner Slice\nMenu:\nPizza 12", 3))
    assertEquals("Looks like a menu: 2 pages", Share.guessLine(Kind.RESTAURANT, "", 2))
    assertEquals("Looks like an event: Spring fair", Share.guessLine(Kind.EVENT, "Title: Spring fair", 2))
  }

  @Test fun aPreviewShowsWhatWouldBeSavedThenTheSameShareSavesIt() {
    val ok = """{"kind":"restaurant","summary":"Ready to add: Corner Slice","link":"https://k/#/meals?restaurant=r1","review":true,"preview":{"title":"Corner Slice","imageUrl":null,"exists":true,"lines":["Pizza","555-0100"],"already":"Already in Kinwall: 12 new items will be added.","token":"t1"}}"""
    val r = (Share.outcome(200, ok) as Share.Outcome.Done).result
    assertEquals(Share.Preview("Corner Slice", null, listOf("Pizza", "555-0100"), "Already in Kinwall: 12 new items will be added.", "t1"), r.preview)
    assertEquals("Check the restaurant", Share.checkTitle(Kind.RESTAURANT))
    // The sheet asks for a preview; the save is the same share without it, with the preview's token.
    val save = Share.Request(kind = Kind.RESTAURANT, text = "Name: Corner Slice", preview = true).saving(r)
    assertEquals(setOf("kind", "text", "token"), JSONObject(save.json()).keys().asSequence().toSet())
    // An older Kinwall saves it straight away: no preview.
    assertNull((Share.outcome(200, """{"kind":"recipe","summary":"Imported Tacos","link":"https://k/#/meals?recipe=x","review":false}""") as Share.Outcome.Done).result.preview)
  }

  // The app's sign-in (Share.freshTokens): the app refreshes the same tokens apart from the share sheet.
  private val now = 1_800_000_000_000L
  private fun tokens(refresh: String, inMinutes: Int) = JSONObject().put("baseURL", "https://kinwall.family/").put("clientId", "c")
    .put("accessToken", "a-$refresh").put("refreshToken", refresh).put("expiresAt", (now + inMinutes * 60_000L).toDouble()).put("scope", "kinwall:admin")
  private val reply = JSONObject().put("access_token", "a-r2").put("refresh_token", "r2").put("expires_in", 3600).put("scope", "kinwall:admin")

  @Test fun currentTokensGoAsTheyAre() {
    val t = tokens("r1", 60)
    assertEquals(t, Share.freshTokens(t, now, { null }, { throw AssertionError("refreshed") }, { true }))
  }

  @Test fun aRefreshIsSavedBeforeUse() {
    val saved = mutableListOf<String>()
    val out = Share.freshTokens(tokens("r1", 2), now, { null }, { reply }, { saved.add(it.getString("refreshToken")); true })
    assertEquals("r2", out?.getString("refreshToken"))
    assertEquals(now + 3_600_000.0, out!!.getDouble("expiresAt"), 0.0)
    assertEquals(listOf("r2"), saved)
  }

  @Test fun aFailedSaveIsTriedAgainAndTheNewPairStillUsed() {
    var tries = 0
    assertEquals("r2", Share.freshTokens(tokens("r1", 2), now, { null }, { reply }, { tries++; false })?.getString("refreshToken"))
    assertEquals(2, tries)
  }

  @Test fun turnedDownAfterTheAppRotatedThemUsesTheirs() {
    assertEquals("r2", Share.freshTokens(tokens("r1", 2), now, { tokens("r2", 60) }, { null }, { true })?.getString("refreshToken"))
  }

  @Test fun turnedDownWithNothingNewerMeansSignIn() {
    assertNull(Share.freshTokens(tokens("r1", 2), now, { tokens("r1", 2) }, { null }, { true }))
    assertNull(Share.freshTokens(tokens("r1", 2), now, { null }, { null }, { true }))
  }
}
