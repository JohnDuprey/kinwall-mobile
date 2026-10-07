package family.kinwall.nativemodule

import family.kinwall.nativemodule.Share.Found
import family.kinwall.nativemodule.Share.Kind
import family.kinwall.nativemodule.Share.Type
import org.json.JSONObject
import org.junit.Assert.assertEquals
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
    assertEquals("a month alone isn't a date", "", Share.headers(Kind.EVENT, listOf(Found(Type.DATE_TIME, "May", tenAm, 1)), ny))
    assertEquals("Date: May 9\n\nSpring fair\nMay 9", Share.withHeaders(Kind.EVENT, listOf(Found(Type.DATE_TIME, "May 9", tenAm, 3)), " Spring fair\nMay 9 ", ny))
  }

  @Test fun restaurantAndBookHeaders() {
    val found = listOf(Found(Type.PHONE, "(555) 010-1234"), Found(Type.ADDRESS, "1 Main St"), Found(Type.URL, "joespizza.example"), Found(Type.ISBN, "978-0-306-40615-7"))
    assertEquals("Phone: (555) 010-1234\nAddress: 1 Main St\nWebsite: joespizza.example", Share.headers(Kind.RESTAURANT, found))
    assertEquals("ISBN: 978-0-306-40615-7", Share.headers(Kind.BOOK, found))
    assertEquals("Joe's menu", Share.withHeaders(Kind.BOOK, emptyList(), "Joe's menu"))
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
}
