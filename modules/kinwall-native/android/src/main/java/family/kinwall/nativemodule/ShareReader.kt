package family.kinwall.nativemodule

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Task
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.nl.entityextraction.Entity
import com.google.mlkit.nl.entityextraction.EntityExtraction
import com.google.mlkit.nl.entityextraction.EntityExtractionParams
import com.google.mlkit.nl.entityextraction.EntityExtractorOptions
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** A shared photo's words, read on the device for POST /api/share (ShareActivity.kt), all with ML Kit:
 * an ISBN barcode means a book (barcode scanning, the bundled model expo-camera already ships); else
 * text recognition (Latin, through Google Play services) reads the words; entity extraction finds
 * dates, places, phone numbers, websites and ISBNs (Share.headers); and on a phone with Gemini Nano
 * (ML Kit GenAI Prompt API) the model guesses what it is and tidies the words, like the iOS model step
 * (Share.guessPrompt); for a menu only its name, phone, address and website, with the menu as read
 * (Share.menuText). The words keep a row's pieces on one line and a price read apart on its row
 * (Share.readingOrder), with what a closer look at each quarter adds (Share.merged), and a QR code
 * becomes a menu's ordering or menu link when the words beside it say so (Share.linkLines). Entity
 * extraction and Gemini Nano need Android 8; older phones skip them. */
object ShareReader {
  data class Read(val isbn: String?, val text: String?, val links: List<String> = emptyList())

  /** A photo's ISBN (from its barcode), else its words and its QR codes' lines for a menu ("Order
   * online: …"). Null when it can't be opened. */
  suspend fun read(context: Context, uri: Uri): Read? {
    val bitmap = try { downscaled(context, uri) } catch (e: Exception) { null } ?: return null
    val image = InputImage.fromBitmap(bitmap, 0)
    val scanner = BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_EAN_13, Barcode.FORMAT_QR_CODE).build())
    val codes = try { scanner.process(image).await() } catch (e: Exception) { emptyList() } finally { scanner.close() }
    codes.firstNotNullOfOrNull { if (it.format == Barcode.FORMAT_EAN_13) Share.isbnBarcode(it.rawValue) else null }?.let { return Read(it, null) }
    val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    // The Play services model downloads with the app (the manifest's vision DEPENDENCIES); until it
    // has, this fails and the photo has no words.
    val words = try {
      // The photo read again in four overlapping quarters: a whole-page read misses small text (a
      // menu's last prices by its mailing label) and reads it up close (Share.merged).
      val w = bitmap.width
      val h = bitmap.height
      val tiles = listOf(0.0 to 0.0, 0.45 to 0.0, 0.0 to 0.45, 0.45 to 0.45).flatMap { (cx, cy) ->
        val tile = Bitmap.createBitmap(bitmap, (cx * w).toInt(), (cy * h).toInt(), (0.55 * w).toInt(), (0.55 * h).toInt())
        lines(recognizer, InputImage.fromBitmap(tile, 0), (cx * w).toInt(), (cy * h).toInt())
      }
      Share.merged(lines(recognizer, image, 0, 0), tiles)
    } catch (e: Exception) { emptyList() } finally { recognizer.close() }
    val qr = codes.filter { it.format == Barcode.FORMAT_QR_CODE }.mapNotNull { c -> c.rawValue?.let { v -> c.boundingBox?.let { line(v, it) } } }
    return Read(null, Share.readingOrder(words).takeIf { it.isNotBlank() }, Share.linkLines(qr, words))
  }

  private fun line(text: String, box: android.graphics.Rect, slope: Double = 0.0) =
    Share.TextLine(text, box.left.toDouble(), box.top.toDouble(), box.width().toDouble(), box.height().toDouble(), slope)

  /** ML Kit's lines on an image, moved by (dx, dy) onto the whole photo, with each one's tilt from its corners. */
  private suspend fun lines(recognizer: com.google.mlkit.vision.text.TextRecognizer, image: InputImage, dx: Int, dy: Int) =
    recognizer.process(image).await().textBlocks.flatMap { b ->
      b.lines.mapNotNull { l ->
        val c = l.cornerPoints
        val slope = if (c != null && c.size >= 2 && c[1].x != c[0].x) (c[1].y - c[0].y).toDouble() / (c[1].x - c[0].x) else 0.0
        l.boundingBox?.let { line(l.text, android.graphics.Rect(it.left + dx, it.top + dy, it.right + dx, it.bottom + dy), slope) }
      }
    }

  /** `links`: the QR code lines for a menu, one of each kind, the first photo's first. */
  data class Pages(val isbn: String?, val pages: List<String>, val links: List<String> = emptyList())

  /** Several photos (or one), read one at a time so only one is in memory: an ISBN on any of them
   * (a book), else each one's words in the order shared. `reading` is told which one is being read.
   * Null when none could be opened. */
  suspend fun read(context: Context, uris: List<Uri>, reading: (Int) -> Unit): Pages? {
    val pages = mutableListOf<String>()
    val links = mutableListOf<String>()
    var opened = false
    for ((n, uri) in uris.withIndex()) {
      reading(n)
      val read = read(context, uri) ?: continue
      opened = true
      if (read.isbn != null) return Pages(read.isbn, emptyList())
      read.text?.let { pages += it }
      for (l in read.links) if (links.none { it.substringBefore(':') == l.substringBefore(':') }) links += l
    }
    return if (opened) Pages(null, pages, links) else null
  }

  /** Gemini Nano's guess at what the words are, in the lines Kinwall reads; null without it, or when
   * it isn't sure. Words too long for it in one go (Share.chunks): the first part decides. A menu:
   * its header lines over all the words as read (Share.menuText). */
  suspend fun guess(pages: List<String>): Pair<Share.Kind, String>? {
    val guess = ask(Share.chunks(pages).firstOrNull()?.let(Share::guessPrompt))?.let(Share::guess) ?: return null
    return if (guess.first == Share.Kind.RESTAURANT) guess.first to Share.menuText(guess.second, Share.joinPages(pages)) else guess
  }

  /** The words in a kind's lines (after the person picked it), or null without Gemini Nano. The model
   * reads the first part (Share.chunks); a menu is its header lines over all the words as read. */
  suspend fun tidied(pages: List<String>, kind: Share.Kind): String? {
    val answer = ask(Share.chunks(pages).firstOrNull()?.let { Share.prompt(kind, it) }) ?: return null
    return if (kind == Share.Kind.RESTAURANT) Share.menuText(answer, Share.joinPages(pages)) else answer
  }

  /** At most 3000 px on the long side, turned upright: plenty for reading text, and a 50 MP photo
   * decoded whole would be ~200 MB. */
  private fun downscaled(context: Context, uri: Uri): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 3000) sample *= 2
    val bitmap = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return null
    val degrees = context.contentResolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0
    return if (degrees == 0) bitmap else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees.toFloat()) }, true)
  }

  /** Dates, places, phone numbers, websites and ISBNs in the words (English). The model (~5 MB)
   * downloads the first time; without a connection then, or on Android 7, nothing is found. */
  suspend fun entities(text: String): List<Share.Found> {
    if (Build.VERSION.SDK_INT < 26 || text.isBlank()) return emptyList()
    val extractor = EntityExtraction.getClient(EntityExtractorOptions.Builder(EntityExtractorOptions.ENGLISH).build())
    return try {
      withTimeoutOrNull(15_000) { extractor.downloadModelIfNeeded().await(); true } ?: return emptyList<Share.Found>().also { android.util.Log.w("KinwallShare", "entity model download timed out") }
      val types = setOf(Entity.TYPE_DATE_TIME, Entity.TYPE_ADDRESS, Entity.TYPE_PHONE, Entity.TYPE_URL, Entity.TYPE_ISBN)
      extractor.annotate(EntityExtractionParams.Builder(text).setEntityTypesFilter(types).build()).await().flatMap { a ->
        a.entities.mapNotNull { e ->
          when (e.type) {
            Entity.TYPE_DATE_TIME -> e.asDateTimeEntity()?.let { Share.Found(Share.Type.DATE_TIME, a.annotatedText, it.timestampMillis, it.dateTimeGranularity) }
            Entity.TYPE_ADDRESS -> Share.Found(Share.Type.ADDRESS, a.annotatedText.replace(Regex("\\s*\\n\\s*"), ", "))
            Entity.TYPE_PHONE -> Share.Found(Share.Type.PHONE, a.annotatedText)
            Entity.TYPE_URL -> Share.Found(Share.Type.URL, a.annotatedText)
            Entity.TYPE_ISBN -> Share.Found(Share.Type.ISBN, a.annotatedText)
            else -> null
          }
        }
      }
    } catch (e: Exception) {
      android.util.Log.w("KinwallShare", "entity extraction failed", e)
      emptyList()
    } finally {
      extractor.close()
    }
  }

  /** Gemini Nano's answer, or null: no Gemini Nano on this phone (or not downloaded yet; this never
   * starts the download), an error, or over `limit` ms. */
  suspend fun ask(prompt: String?, limit: Long = 20_000): String? {
    if (prompt == null || Build.VERSION.SDK_INT < 26) return null
    return try {
      withTimeoutOrNull(limit) {
        val model = Generation.getClient()
        try {
          if (model.checkStatus() != FeatureStatus.AVAILABLE) null
          else model.generateContent(prompt).candidates.firstOrNull()?.text?.takeIf { it.isNotBlank() }
        } finally {
          model.close()
        }
      }
    } catch (e: Exception) {
      if (e is kotlinx.coroutines.CancellationException) throw e
      null
    }
  }

  private suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { c ->
    addOnSuccessListener { c.resume(it) }
    addOnFailureListener { c.resumeWithException(it) }
    addOnCanceledListener { c.cancel() }
  }
}
