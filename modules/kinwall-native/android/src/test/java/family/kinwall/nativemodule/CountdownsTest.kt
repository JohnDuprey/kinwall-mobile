package family.kinwall.nativemodule

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// The cooking timer notification's words (Countdowns.cooking). Run after a prebuild: cd android && ./gradlew :kinwall-native:testReleaseUnitTest
class CountdownsTest {
  // A 5–6 min range started at 0 (web/src/liveActivity.ts): check at 300 000, done at 360 000.
  private val range = JSONObject("""{"recipe":"Tuesday Tacos","timer":"5–6 min","step":"Step 2","endsAt":360000,"done":false,"more":0,
    "alarms":[{"at":360000,"title":"Time's up: 5–6 min","body":"Tuesday Tacos · Step 2"}],
    "checks":[{"at":300000,"title":"Check it: 5–6 min","body":"Tuesday Tacos · Step 2"}],
    "check":{"at":300000,"before":"Check at 5:00","after":"Check now · up to 1:00 more"}}""")

  @Test fun rangeCountsToTheCheckThenTheEnd() {
    val before = Countdowns.cooking(range, 60_000)!!
    assertEquals(listOf("Check at 5:00", "5–6 min · Step 2 · Tuesday Tacos", 300_000L, 300_000L), listOf(before.title, before.text, before.countdownTo, before.next))
    val after = Countdowns.cooking(range, 300_000)!!
    assertEquals(listOf("Check now · up to 1:00 more", 360_000L, 360_000L), listOf(after.title, after.countdownTo, after.next))
    val done = Countdowns.cooking(range, 360_000)!!
    assertEquals(listOf("Done: 5–6 min", "Step 2 · Tuesday Tacos", null), listOf(done.title, done.text, done.countdownTo))
  }

  @Test fun singleTimeAsBefore() {
    val one = JSONObject("""{"recipe":"Timer","timer":"Rice","step":"","endsAt":900000,"done":false,"more":1,"alarms":[]}""")
    val c = Countdowns.cooking(one, 0)!!
    assertEquals(listOf("Rice", "+1 more · Timer", 900_000L), listOf(c.title, c.text, c.countdownTo))
    assertNull("long done: gone", Countdowns.cooking(one, 900_000 + 31 * 60_000))
  }
}
