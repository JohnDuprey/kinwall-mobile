import Foundation
import ImageIO
import KinwallKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// A shared photo's text, for POST /api/share (KinwallKit Share.swift), read on the device: compiled
// into the app (Add to Kinwall, SiriIntents.swift) and the share extension (targets/share, through
// plugins/withKinwallNative.js). An ISBN barcode means a book. Otherwise Vision reads the words, and
// on an iPhone with Apple Intelligence (iOS 26) the on-device model says what it is and rewrites it
// into the lines Kinwall reads (Share.guessPrompt, Share.prompt). Without the model, or when it fails
// or takes over 20 s, the words go as they were read. FoundationModels is weak-linked on its own (the
// linker does it for a framework newer than the iOS 17 target), so iOS 17-25 still launch.
enum ShareReader {
    /// A photo's ISBN (from its barcode), else its words. Nil when it can't be read.
    static func read(_ image: Data) -> (isbn: String?, text: String?)? {
        guard let cg = downscaled(image) else { return nil }
        if let isbn = isbn(in: cg) { return (isbn, nil) }
        return (nil, recognizedText(in: cg)?.nilIfBlank)
    }

    /// Several photos (or one), read one at a time so only one is in memory: an ISBN on any of them
    /// (a book), else each one's words in the order shared. `load` gives the nth photo's data;
    /// `reading` is told which one is being read. Nil when none could be opened.
    @MainActor static func read(count: Int, load: (Int) async -> Data?, reading: (Int) -> Void) async -> (isbn: String?, pages: [String])? {
        var pages: [String] = [], opened = false
        for n in 0..<count {
            reading(n)
            guard let data = await load(n), let read = read(data) else { continue }
            opened = true
            if let isbn = read.isbn { return (isbn, []) }
            if let text = read.text { pages.append(text) }
        }
        return opened ? (nil, pages) : nil
    }

    /// The model's guess at what the words are, in the lines Kinwall reads; nil without Apple
    /// Intelligence, or when it isn't sure. Words too long for the model in one go (Share.chunks):
    /// the first part decides, and a menu's other parts add their menu lines.
    static func guess(_ pages: [String]) async -> (kind: Share.Kind, text: String)? {
        let parts = Share.chunks(pages)
        guard let first = parts.first, let guess = await ask(Share.guessPrompt(text: first)).flatMap(Share.guess) else { return nil }
        guard guess.kind == .restaurant, parts.count > 1 else { return guess }
        return (guess.kind, await rest(of: parts, after: guess.text))
    }

    /// The words in a kind's lines (after the person picked it), or nil without the model. A long
    /// menu goes part by part (Share.chunks): the first part gives the name and the other header
    /// lines, every part its menu lines; a part the model fails on goes as it was read.
    static func tidied(_ pages: [String], kind: Share.Kind) async -> String? {
        let parts = Share.chunks(pages)
        guard let first = parts.first, let prompt = Share.prompt(kind, text: first), let answer = await ask(prompt) else { return nil }
        return kind == .restaurant && parts.count > 1 ? await rest(of: parts, after: answer) : answer
    }

    private static func rest(of parts: [String], after first: String) async -> String {
        var answers = [first]
        for part in parts.dropFirst() { answers.append(await ask(Share.morePrompt(text: part)) ?? part) }
        return Share.joinPages(answers)
    }

    /// At most 3000 px on the long side, turned upright: a 48 MP photo decoded whole would be ~190 MB,
    /// over a share extension's memory limit; this is plenty for reading text.
    static func downscaled(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 3000, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// An EAN-13 that's an ISBN (978/979), off the back cover's barcode.
    static func isbn(in image: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap(\.payloadStringValue).first { $0.count == 13 && ($0.hasPrefix("978") || $0.hasPrefix("979")) }
    }

    static func recognizedText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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
