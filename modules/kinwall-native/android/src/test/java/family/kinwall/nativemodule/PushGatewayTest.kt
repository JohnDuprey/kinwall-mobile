package family.kinwall.nativemodule

import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

// The gateway's raw r||s signature (PushGateway.p1363). Run after a prebuild: cd android && ./gradlew :kinwall-native:testReleaseUnitTest
class PushGatewayTest {
  private fun bytes(vararg b: Int) = ByteArray(b.size) { b[it].toByte() }

  @Test fun derSignaturesVerifyAsRaw() {
    val key = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    val data = """{"protocol":"kinwall-android-push-v1","server":"https://family.example","kind":"android-alert"}""".toByteArray()
    // Enough signatures that some have r or s shorter than 32 bytes or with a sign byte.
    repeat(128) {
      val raw = PushGateway.p1363(Signature.getInstance("SHA256withECDSA").apply { initSign(key.private); update(data) }.sign())
      assertEquals(64, raw.size)
      val verify = Signature.getInstance("SHA256withECDSAinP1363Format")
      verify.initVerify(key.public); verify.update(data); assertTrue(verify.verify(raw))
      verify.initVerify(key.public); verify.update("changed".toByteArray()); assertFalse(verify.verify(raw))
    }
  }

  @Test fun shortValuesArePadded() {
    val raw = PushGateway.p1363(bytes(0x30, 6, 2, 1, 1, 2, 1, 2))
    assertArrayEquals(ByteArray(31) + 1 + ByteArray(31) + 2, raw)
  }

  @Test fun malformedDerIsRejected() {
    listOf(bytes(), bytes(0x30, 0), bytes(0x31, 6, 2, 1, 1, 2, 1, 2), bytes(0x30, 6, 2, 1, 0xff, 2, 1, 2),
      bytes(0x30, 7, 2, 2, 0, 1, 2, 1, 2), bytes(0x30, 6, 2, 1, 1, 2, 1, 2, 0), bytes(0x30, 6, 2, 0, 2, 2, 1, 2),
      bytes(0x30, 38, 2, 33, *IntArray(33) { 1 }, 2, 1, 2),
    ).forEach { assertThrows(IllegalArgumentException::class.java) { PushGateway.p1363(it) } }
  }
}
