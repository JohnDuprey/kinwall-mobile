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
 * (Share.guessPrompt). Entity extraction and Gemini Nano need Android 8; older phones skip them. */
object ShareReader {
  data class Read(val isbn: String?, val text: String?)

  /** A photo's ISBN (from its barcode), else its words. Null when it can't be opened. */
  suspend fun read(context: Context, uri: Uri): Read? {
    val bitmap = try { downscaled(context, uri) } catch (e: Exception) { null } ?: return null
    val image = InputImage.fromBitmap(bitmap, 0)
    val scanner = BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_EAN_13).build())
    val isbn = try { scanner.process(image).await().firstNotNullOfOrNull { Share.isbnBarcode(it.rawValue) } } catch (e: Exception) { null } finally { scanner.close() }
    if (isbn != null) return Read(isbn, null)
    val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    // The Play services model downloads with the app (the manifest's vision DEPENDENCIES); until it
    // has, this fails and the photo has no words.
    val text = try { recognizer.process(image).await().text } catch (e: Exception) { null } finally { recognizer.close() }
    return Read(null, text?.takeIf { it.isNotBlank() })
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
