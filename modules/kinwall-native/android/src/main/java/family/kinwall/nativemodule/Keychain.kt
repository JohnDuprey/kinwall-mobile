package family.kinwall.nativemodule

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Android's side of keychainGet/keychainSet (src/sharedKey.ts, src/oauth.ts, src/demo.ts): each
 * value AES-GCM encrypted with a key that never leaves the Android Keystore. Kept here, not in
 * expo-secure-store, so "Got it" (Countdowns.kt) can read the widgets' key with the app closed.
 * `shared` (iOS's Keychain group) means nothing on Android: there's one app. */
object Keychain {
  private const val ALIAS = "family.kinwall.keychain"
  private const val PREFS = "family.kinwall.keychain"

  private fun key(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
    val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    gen.init(
      KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .build()
    )
    return gen.generateKey()
  }

  fun get(context: Context, service: String): String? {
    val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(service, null) ?: return null
    return try {
      val bytes = Base64.decode(saved, Base64.NO_WRAP)
      val cipher = Cipher.getInstance("AES/GCM/NoPadding")
      cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
      String(cipher.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
    } catch (e: Exception) {
      null // a key lost with a restore to another phone: signed out, sign in again
    }
  }

  /** Written to disk before it returns (a rotated refresh token lost to a killed process would sign
   * the phone out): false when it couldn't be. */
  fun set(context: Context, service: String, value: String?): Boolean {
    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    if (value == null) return prefs.remove(service).commit()
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key())
    val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
    return prefs.putString(service, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()
  }
}
