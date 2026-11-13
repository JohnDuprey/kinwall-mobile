package family.kinwall.nativemodule

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import kotlin.concurrent.thread

/** Contacts (vCards) shared to the app: MainActivity (plugins/withKinwallNative.js) hands over what
 * another app sent, read here off the main thread; takeSharedContacts (KinwallNativeModule) waits for
 * it and takes the text for the page's contact review (src/WebShell.tsx). */
object SharedContacts {
  /** 2 MB in all: hundreds of plain contact cards, or dozens with photos. A share over it is
   * dropped (Contacts still opens), never cut short into a half contact. */
  private const val MAX_BYTES = 2 * 1024 * 1024
  private const val WAIT_MS = 3000L

  @Volatile private var reading: Thread? = null

  private fun file(context: Context) = File(context.cacheDir, "shared-contacts.vcf")

  /** Only content: URIs (a file: path could point into this app's own storage); `text` is the
   * share's EXTRA_TEXT, used when there's no readable stream. */
  @JvmStatic
  fun read(context: Context, uris: List<Uri>, text: String?) {
    val app = context.applicationContext
    reading = thread(name = "shared-contacts") {
      val file = file(app)
      try {
        val parts = uris.filter { it.scheme == ContentResolver.SCHEME_CONTENT }.map { uri ->
          app.contentResolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
              val n = input.read(buffer)
              if (n < 0) break
              out.write(buffer, 0, n)
              if (out.size() > MAX_BYTES) throw IOException("Shared contacts too large")
            }
            out.toString("UTF-8")
          } ?: ""
        }
        val vcards = parts.joinToString("\r\n").ifBlank { text.orEmpty() }
        if (vcards.length <= MAX_BYTES && vcards.contains("BEGIN:VCARD", ignoreCase = true)) file.writeText(vcards) else file.delete()
      } catch (e: Exception) {
        file.delete()
      }
    }
  }

  /** The shared vCards, once; null when there are none (or the read is still going after 3 s). */
  @JvmStatic
  fun take(context: Context): String? {
    reading?.join(WAIT_MS)
    val file = file(context)
    return if (!file.exists()) null else file.readText().also { file.delete() }
  }
}
