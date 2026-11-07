package family.kinwall.nativemodule

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.google.android.gms.tasks.Tasks
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.TimeUnit

/** The self-hosted Android push gateway's proof (src/androidPushGateway.ts, docs/CHORE-NOTIFICATIONS.md):
 * a P-256 key that never leaves the Android Keystore signs the gateway's exact clientData, and a
 * standard Play Integrity token is bound to the same SHA-256. Google's verdict is the attestation;
 * the signature only proves this install holds the key. Only the shell calls these, never the page.
 * The Cloud project NUMBER comes from the manifest (plugins/withAndroidPushGateway.js); without it, or
 * in a debuggable build, this is unsupported and the app keeps its local reminders. */
object PushGateway {
  private const val ALIAS = "family.kinwall.pushgateway"
  private const val PROJECT = "family.kinwall.PLAY_INTEGRITY_PROJECT_NUMBER"
  private val url = Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP

  private fun project(context: Context): Long? {
    val info = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
    if (info.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) return null
    return info.metaData?.getString(PROJECT)?.removePrefix("project:")?.toLongOrNull()?.takeIf { it > 0 }
  }

  fun supported(context: Context) = project(context) != null

  private fun store() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

  private fun key(): PrivateKey {
    (store().getKey(ALIAS, null) as? PrivateKey)?.let { return it }
    val gen = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
    gen.initialize(
      KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
        .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
        .setDigests(KeyProperties.DIGEST_SHA256)
        .build()
    )
    return gen.generateKeyPair().private
  }

  /** Standard base64 DER SPKI, and its lowercase hex SHA-256 (the clientData's keyId). */
  fun publicKey(): Map<String, String> {
    key()
    val spki = store().getCertificate(ALIAS).publicKey.encoded
    return mapOf("publicKey" to Base64.encodeToString(spki, Base64.NO_WRAP), "keyId" to sha256(spki).joinToString("") { "%02x".format(it) })
  }

  /** Blocking; AsyncFunction runs it off the main thread. Each Play step is bounded so a stuck Play
   * Store fails (and keeps local reminders) instead of hanging registration. */
  fun proof(context: Context, clientData: String): Map<String, String> {
    val number = project(context) ?: throw IllegalStateException("Android app verification unavailable")
    val data = clientData.toByteArray(Charsets.UTF_8)
    val signer = Signature.getInstance("SHA256withECDSA").apply { initSign(key()); update(data) }
    val signature = Base64.encodeToString(p1363(signer.sign()), url)
    val manager = IntegrityManagerFactory.createStandard(context.applicationContext)
    val provider = Tasks.await(manager.prepareIntegrityToken(PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(number).build()), 30, TimeUnit.SECONDS)
    val hash = Base64.encodeToString(sha256(data), url)
    val token = Tasks.await(provider.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build()), 30, TimeUnit.SECONDS)
    return mapOf("integrityToken" to token.token(), "signature" to signature)
  }

  private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)

  /** Android's ECDSA signature is DER (SEQUENCE of two INTEGERs); the gateway takes raw r||s, 32
   * bytes each. Strict: anything but one minimal, positive P-256 r and s is rejected. */
  fun p1363(der: ByteArray): ByteArray {
    fun bad(): Nothing = throw IllegalArgumentException("Bad ECDSA signature")
    if (der.size < 8 || der[0] != 0x30.toByte() || der[1].toInt() and 0xff != der.size - 2) bad()
    val out = ByteArray(64)
    var at = 2
    for (half in 0..1) {
      if (at + 2 > der.size || der[at] != 0x02.toByte()) bad()
      val len = der[at + 1].toInt() and 0xff
      at += 2
      if (len == 0 || at + len > der.size || der[at] < 0) bad()
      var value = der.copyOfRange(at, at + len)
      if (value.size > 1 && value[0] == 0.toByte()) {
        if (value[1] >= 0) bad() // not minimal
        value = value.copyOfRange(1, value.size)
      }
      if (value.size > 32) bad()
      value.copyInto(out, half * 32 + 32 - value.size)
      at += len
    }
    if (at != der.size) bad()
    return out
  }
}
