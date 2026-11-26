import UIKit
import WebKit

/// Search only the tagged shell wrapper using public view APIs. No dependency on RNCWebView's
/// private fields or its Paper/Fabric wrapper classes; the live WKWebView owns print layout.
final class PagePrinting {
    private var presenting = false

    static func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { webView(in: $0) }.first
    }

    func printPage(in host: UIView, title: String) throws {
        guard UIPrintInteractionController.isPrintingAvailable,
              let web = Self.webView(in: host), web.window != nil else {
            throw NSError(domain: "KinwallPrint", code: 1, userInfo: [NSLocalizedDescriptionKey: "The recipe is not ready to print."])
        }
        guard !presenting else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Kinwall recipe" : title
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = nil
        controller.printingItems = nil
        controller.printPageRenderer = nil
        controller.printFormatter = web.viewPrintFormatter()
        presenting = true
        let finished: UIPrintInteractionController.CompletionHandler = { [weak self] _, _, _ in self?.presenting = false }
        let shown = UIDevice.current.userInterfaceIdiom == .pad
            ? controller.present(from: web.bounds, in: web, animated: true, completionHandler: finished)
            : controller.present(animated: true, completionHandler: finished)
        if !shown {
            presenting = false
            throw NSError(domain: "KinwallPrint", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not open printing."])
        }
    }
}
