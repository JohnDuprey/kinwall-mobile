package family.kinwall.nativemodule

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.print.PrintJob
import android.print.PrintManager
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView

/** Walk only the tagged shell wrapper, using public view APIs rather than RNCWebView internals. */
internal class PagePrinting {
  private var job: PrintJob? = null

  companion object {
    fun supported(context: Context) = context.packageManager.hasSystemFeature(PackageManager.FEATURE_PRINTING)

    fun webView(view: View): WebView? {
      if (view is WebView) return view
      if (view is ViewGroup) for (index in 0 until view.childCount) {
        webView(view.getChildAt(index))?.let { return it }
      }
      return null
    }
  }

  // Called on the UI queue. WebView supports one active print job at a time.
  fun printPage(activity: Activity, host: View, title: String) {
    check(supported(activity)) { "Printing is unavailable." }
    val web = checkNotNull(webView(host)) { "The recipe is not ready to print." }
    check(web.isAttachedToWindow) { "The recipe is not ready to print." }
    if (job?.let { !it.isCompleted && !it.isCancelled && !it.isFailed } == true) return
    val name = title.ifBlank { "Kinwall recipe" }
    val manager = activity.getSystemService(Context.PRINT_SERVICE) as PrintManager
    job = manager.print(name, web.createPrintDocumentAdapter(name), null)
  }
}
