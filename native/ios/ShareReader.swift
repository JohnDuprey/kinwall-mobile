import Foundation
import ImageIO
import KinwallKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// A shared photo's text, for POST /api/share (KinwallKit Share.swift), read on the device: compiled
// into the app (Add to Kinwall, SiriIntents.swift) and the share extension (targets/share, through
// plugins/withKinwallNative.js). An ISBN barcode means a book. Otherwise Vision reads the words (a
// row's pieces and a price read apart put back on one line, Share.readingOrder; the photo read
// again in quarters for small text a whole-page read misses, Share.merged) and any QR code (Share.linkLines), and on an
// iPhone with Apple Intelligence (iOS 26) the on-device model says what it is and rewrites it into the
// lines Kinwall reads (Share.guessPrompt, Share.prompt); for a menu only its name, phone, address and
// website, with the menu as read (Share.menuText). Without the model, or when it fails or takes over
// 20 s, the words go as they were read. FoundationModels is weak-linked on its own (the
// linker does it for a framework newer than the iOS 17 target), so iOS 17-25 still launch.
enum ShareReader {
    /// A photo's ISBN (from its barcode), else its words and its QR codes' lines for a menu
    /// ("Order online: …"). Nil when it can't be read.
    static func read(_ image: Data) -> (isbn: String?, text: String?, links: [String])? {
        guard let cg = downscaled(image) else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg)
        let codes = VNDetectBarcodesRequest()
        codes.symbologies = [.ean13, .qr]
        try? handler.perform([codes])
        if let isbn = codes.results?.filter({ $0.symbology == .ean13 }).compactMap(\.payloadStringValue)
            .first(where: { $0.count == 13 && ($0.hasPrefix("978") || $0.hasPrefix("979")) }) { return (isbn, nil, []) }
        let words = Share.merged(recognizedLines(handler), tiles(cg))
        let qr = codes.results?.filter { $0.symbology == .qr }.compactMap { c in c.payloadStringValue.map { line($0, c.boundingBox) } } ?? []
        return (nil, Share.readingOrder(words).nilIfBlank, Share.linkLines(codes: qr, words: words))
    }

    /// Several photos (or one), read one at a time so only one is in memory: an ISBN on any of them
    /// (a book), else each one's words in the order shared. `load` gives the nth photo's data;
    /// `reading` is told which one is being read. Nil when none could be opened.
    /// `links`: the QR code lines for a menu, one of each kind, the first photo's first.
    @MainActor static func read(count: Int, load: (Int) async -> Data?, reading: (Int) -> Void) async -> (isbn: String?, pages: [String], links: [String])? {
        var pages: [String] = [], links: [String] = [], opened = false
        for n in 0..<count {
            reading(n)
            guard let data = await load(n), let read = read(data) else { continue }
            opened = true
            if let isbn = read.isbn { return (isbn, [], []) }
            if let text = read.text { pages.append(text) }
            for l in read.links where !links.contains(where: { $0.prefix(while: { $0 != ":" }) == l.prefix(while: { $0 != ":" }) }) { links.append(l) }
        }
        return opened ? (nil, pages, links) : nil
    }

    /// The model's guess at what the words are, in the lines Kinwall reads; nil without Apple
    /// Intelligence, or when it isn't sure. Words too long for the model in one go (Share.chunks):
    /// the first part decides. A menu: its header lines over all the words as read (Share.menuText).
    static func guess(_ pages: [String]) async -> (kind: Share.Kind, text: String)? {
        guard let first = Share.chunks(pages).first, let guess = await ask(Share.guessPrompt(text: first)).flatMap(Share.guess) else { return nil }
        return guess.kind == .restaurant ? (guess.kind, Share.menuText(guess.text, raw: Share.joinPages(pages))) : guess
    }

    /// The words in a kind's lines (after the person picked it), or nil without the model. The model
    /// reads the first part (Share.chunks); a menu is its header lines over all the words as read.
    static func tidied(_ pages: [String], kind: Share.Kind) async -> String? {
        guard let first = Share.chunks(pages).first, let prompt = Share.prompt(kind, text: first), let answer = await ask(prompt) else { return nil }
        return kind == .restaurant ? Share.menuText(answer, raw: Share.joinPages(pages)) : answer
    }

    /// At most 3000 px on the long side, turned upright: a 48 MP photo decoded whole would be ~190 MB,
    /// over a share extension's memory limit; this is plenty for reading text.
    static func downscaled(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 3000, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Vision's lines with where they are, in Vision's order (a column at a time).
    static func recognizedLines(_ handler: VNImageRequestHandler) -> [Share.TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? handler.perform([request])
        return request.results?.compactMap { o in
            o.topCandidates(1).first.map { c in
                var l = line(c.string, o.boundingBox)
                if o.topRight.x > o.topLeft.x { l.slope = -(o.topRight.y - o.topLeft.y) / (o.topRight.x - o.topLeft.x) } // the photo's tilt, from the top left
                return l
            }
        } ?? []
    }

    /// The photo read again in four overlapping quarters, as lines on the whole photo: Vision misses
    /// small text on a whole page (a menu's last prices by its mailing label), and reads it up close.
    /// About as long again as reading the whole photo.
    static func tiles(_ image: CGImage) -> [Share.TextLine] {
        let w = Double(image.width), h = Double(image.height), size = 0.55
        return [(0.0, 0.0), (0.45, 0.0), (0.0, 0.45), (0.45, 0.45)].flatMap { cx, cy -> [Share.TextLine] in
            guard let tile = image.cropping(to: CGRect(x: cx * w, y: cy * h, width: size * w, height: size * h)) else { return [] }
            return recognizedLines(VNImageRequestHandler(cgImage: tile)).map {
                Share.TextLine(text: $0.text, x: cx + $0.x * size, y: cy + $0.y * size, width: $0.width * size, height: $0.height * size, slope: $0.slope)
            }
        }
    }

    /// Vision's box (normalized, from the bottom left) as a line from the top left.
    static func line(_ text: String, _ box: CGRect) -> Share.TextLine {
        Share.TextLine(text: text, x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// The on-device model's answer, or nil: no Apple Intelligence, an error, or over `limit` seconds.
    static func ask(_ prompt: String, limit: Double = 20) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            // Whichever comes first; the model's answer is dropped if it comes later (a task group
            // would wait for it).
            let work = Task { try? await LanguageModelSession().respond(to: prompt).content.nilIfBlank }
            let first = Once()
            let answer: String? = await withCheckedContinuation { done in
                Task { let r = await work.value; if first.claim() { done.resume(returning: r) } }
                Task { try? await Task.sleep(for: .seconds(limit)); if first.claim() { work.cancel(); done.resume(returning: nil) } }
            }
            return answer
        }
        #endif
        return nil
    }
}

/// True for the first caller only.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { defer { done = true }; return !done } }
}

extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
