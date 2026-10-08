import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// "Add to Kinwall" from the share sheet (targets/share) and the App Intent (native/ios
/// SiriIntents.swift): what to send to the family's POST /api/share (kinwall's
/// docs/using/share-to-kinwall.md) and what its answer means. The pure parts are tested in
/// ShareTests.swift; reading a photo's text is native/ios/ShareReader.swift.
public enum Share {
    /// What a photo or some text is. A link goes without one: the server reads the page.
    public enum Kind: String, Codable, CaseIterable, Sendable { case recipe, restaurant, book, event }

    public struct Request: Encodable, Equatable, Sendable {
        public var kind: Kind?
        public var url: String?
        public var text: String?
        public var name: String?
        /// An event as the person checked it in the sheet; sent instead of text.
        public var event: EventDraft?
        /// Adds the event to `calendarId` now, instead of answering with a link to check it.
        public var save: Bool?
        public var calendarId: String?
        /// A recipe, restaurant or book: answer with what would be saved (Result.preview) and save
        /// nothing. The share sheet asks for one; Shortcuts and the App Intent save straight away.
        public var preview: Bool?
        /// With the save after a link's preview: its token, so Kinwall doesn't read the page again.
        public var token: String?
        public init(kind: Kind? = nil, url: String? = nil, text: String? = nil, name: String? = nil, event: EventDraft? = nil, save: Bool? = nil, calendarId: String? = nil, preview: Bool? = nil, token: String? = nil) {
            self.kind = kind; self.url = url; self.text = text; self.name = name; self.event = event; self.save = save; self.calendarId = calendarId
            self.preview = preview; self.token = token
        }

        /// The save after `preview`'s card: the same share without preview, with its token.
        public func saving(_ preview: Result) -> Request {
            var r = self
            r.preview = nil
            r.token = preview.preview?.token
            return r
        }
    }

    /// What would be saved (the server's ShareResult preview), for the sheet's card: the photo or
    /// cover, the name, short lines of facts, and a line when it's already in Kinwall.
    public struct Preview: Decodable, Equatable, Sendable {
        public let title: String
        public let imageUrl: String?
        public let lines: [String]
        public let already: String?
        public let token: String?
        public init(title: String, imageUrl: String? = nil, lines: [String] = [], already: String? = nil, token: String? = nil) {
            self.title = title; self.imageUrl = imageUrl; self.lines = lines; self.already = already; self.token = token
        }
    }

    /// The card's title: "Check the recipe", like the event form's "Check the event".
    public static func checkTitle(_ kind: Kind) -> String {
        switch kind { case .recipe: "Check the recipe"; case .restaurant: "Check the restaurant"; case .book: "Check the book"; case .event: "Check the event" }
    }

    /// An event as Kinwall read it (or as the person changed it): a YYYY-MM-DD date and HH:MM times on
    /// the household's clock; no time is all day.
    public struct EventDraft: Codable, Equatable, Sendable {
        public var title: String?, date: String?, time: String?, end: String?, place: String?
        /// Anything else worth knowing (what to bring, how to RSVP); saved as the event's notes.
        public var notes: String?
        public init(title: String? = nil, date: String? = nil, time: String? = nil, end: String? = nil, place: String? = nil, notes: String? = nil) {
            self.title = title; self.date = date; self.time = time; self.end = end; self.place = place; self.notes = notes
        }
    }

    public struct Result: Decodable, Equatable, Sendable {
        public let kind: Kind
        public let summary: String
        public let link: String
        public let review: Bool
        /// An event to check: what Kinwall read, for the sheet's fields (older servers leave it out).
        public var event: EventDraft? = nil
        /// With Request.preview: what would be saved (older servers save it and leave this out).
        public var preview: Preview? = nil
        /// Nothing saved yet (an event or a book to pick): it's checked in Kinwall.
        public var needsReview: Bool { review }
    }

    /// One of the family's calendars (GET /api/calendars).
    public struct FamilyCalendar: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let writable: Bool
        public let enabled: Bool
        public let canEditEvents: Bool?
        /// The family's default calendar for new events (older servers leave it out).
        public let `default`: Bool?
        public init(id: String, name: String, writable: Bool = true, enabled: Bool = true, canEditEvents: Bool? = true, default isDefault: Bool? = nil) {
            self.id = id; self.name = name; self.writable = writable; self.enabled = enabled; self.canEditEvents = canEditEvents; self.default = isDefault
        }
    }

    /// The calendars this phone can add an event to, in Kinwall's order with the family's default
    /// calendar for new events first: the one the app's event sheet picks (web Calendar.tsx).
    public static func addable(_ calendars: [FamilyCalendar]) -> [FamilyCalendar] {
        let open = calendars.filter { $0.writable && $0.enabled && $0.canEditEvents != false }
        return open.filter { $0.default == true } + open.filter { $0.default != true }
    }

    /// What to send for an event: the model's lines, a "---" line, then the words as read, so Kinwall
    /// takes the model's lines first and can fill in what it left out (a street) from the words.
    public static func eventText(_ lines: String?, raw: String) -> String {
        guard let lines = lines?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, lines != raw.trimmingCharacters(in: .whitespacesAndNewlines) else { return raw }
        return "\(lines)\n---\n\(raw)"
    }

    // The sheet's date and time pickers hold the household's wall-clock time as if it were UTC, so
    // nothing shifts with the phone's own time zone.
    public static let utc = TimeZone(identifier: "UTC")!
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = format
        return f
    }
    /// A draft's day and time for a picker; nil when it has no such day or time.
    public static func pickerDate(_ date: String?, _ time: String? = nil) -> Date? {
        guard let date else { return nil }
        return formatter("yyyy-MM-dd HH:mm").date(from: "\(date) \(time ?? "00:00")")
    }
    /// The pickers' values as a draft to send: no times when it's all day.
    public static func draft(title: String, place: String, notes: String = "", day: Date, start: Date, end: Date, allDay: Bool) -> EventDraft {
        let hm = formatter("HH:mm")
        return EventDraft(title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, date: formatter("yyyy-MM-dd").string(from: day),
                          time: allDay ? nil : hm.string(from: start), end: allDay ? nil : hm.string(from: end),
                          place: place.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                          notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
    }

    public enum Outcome: Equatable, Sendable { case done(Result), failed(String) }

    public static let signInMessage = "Open Kinwall and sign in as a grown-up, then share again."

    static func isWeb(_ url: URL) -> Bool { url.scheme == "https" || url.scheme == "http" }

    /// The first web link in some text.
    public static func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first(where: isWeb)
    }

    /// Text that is only a link (what a browser shares), as that link; anything more is text.
    public static func onlyLink(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace), let url = URL(string: t), isWeb(url), url.host != nil else { return nil }
        return url
    }

    /// A link (with no kind, Kinwall reads the page; a Maps place's name helps), else text that
    /// needs its kind. Nil when there's nothing to send, or text with no kind yet ("What is this?" first).
    public static func request(kind: Kind?, url: URL? = nil, text: String? = nil, name: String? = nil) -> Request? {
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let link = url ?? text.flatMap(onlyLink) {
            return Request(kind: kind, url: link.absoluteString, text: nil, name: name?.nilIfEmpty)
        }
        guard let text, let kind, kind != .recipe else { return nil }
        return Request(kind: kind, url: nil, text: text, name: nil)
    }

    /// An Apple Maps place's link (the server's restaurant-import.ts mapsPlace). Maps shares a place
    /// as this link and a location vCard, which isn't a contact.
    public static func isMapsPlace(_ url: URL) -> Bool {
        ["maps.apple.com", "maps.apple"].contains(url.host?.lowercased() ?? "")
    }

    /// A shared vCard's FN (formatted name) line: a Maps place's name.
    public static func vCardName(_ vcard: String) -> String? {
        vcard.split(whereSeparator: \.isNewline).first { $0.uppercased().hasPrefix("FN:") || $0.uppercased().hasPrefix("FN;") }
            .flatMap { $0.split(separator: ":", maxSplits: 1).last }
            .map { String($0).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\,", with: ",") }?.nilIfEmpty
    }

    /// The server's answer as one line: its summary, or what to do about an error without one.
    public static func outcome(status: Int, data: Data) -> Outcome {
        struct Failure: Decodable { let error: String?; let summary: String? }
        if status == 200, let r = try? JSONDecoder().decode(Result.self, from: data) { return .done(r) }
        let f = try? JSONDecoder().decode(Failure.self, from: data)
        if let s = f?.summary?.nilIfEmpty { return .failed(s) }
        let message = switch status {
        case 401, 403: signInMessage // signed out, or a wall screen's or a kid's device
        case 404: "This Kinwall can't take shares yet. Update it, then share again."
        default: "Couldn't add it to Kinwall: \(f?.error ?? "error \(status)")."
        }
        return .failed(message)
    }

    /// The app's own link that opens `link` (a Kinwall address with a #/ route) in the app
    /// (src/links.ts routeFor, to=shared).
    public static func appLink(_ link: String) -> URL? {
        var c = URLComponents(string: "family.kinwall.app:/open")!
        c.queryItems = [URLQueryItem(name: "to", value: "shared"), URLQueryItem(name: "link", value: link)]
        // The app reads it with URLSearchParams, where a bare + is a space (Kinwall's links have them).
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    /// The lines Kinwall reads for each kind: the Shortcut's Use Model prompts (share-to-kinwall.md, meals.md).
    static func format(_ kind: Kind) -> String? {
        switch kind {
        case .restaurant: """
            Name: the restaurant's name
            Cuisine: the kind of food, like Pizza or Thai
            Phone: its phone number
            Address: its address on one line
            Website: its website
            Menu:
            \(menuLines)
            """
        case .book: """
            ISBN: the ISBN, from the barcode's number
            Title: the book's title
            Author: its author
            """
        case .event: """
            Title: a short name for the event
            Date: its date, like Saturday, May 9, 2026
            Time: its start and end time, like 10:00 AM - 2:00 PM
            Place: the venue's name and its full street address and town on one line, like The Rivers Residence, 12 Elm Road, Springfield
            Notes: anything else worth knowing, like what to bring, costs, or how to RSVP
            """
        case .recipe: nil
        }
    }
    static let menuLines = "then each menu section's name on its own line, with each of its items on its own line below it as the item's name and then its price, like \"Large cheese 14.99\""
    static let leaveOut = "Answer in exactly this format and nothing else, and leave out any line you can't find:"

    /// For Apple Intelligence (native/ios/ShareReader.swift): rewrites a photo's text into the lines
    /// Kinwall reads for a kind the person picked.
    public static func prompt(_ kind: Kind, text: String) -> String? {
        let what = switch kind {
        case .restaurant: "a photo of a restaurant menu"
        case .book: "a photo of a book's cover or back"
        case .event: "a flyer, an invitation or a screenshot"
        case .recipe: ""
        }
        return format(kind).map { "This is text from \(what). \(leaveOut)\n\($0)\n\n\(text)" }
    }

    /// For Apple Intelligence: says what the text is and rewrites it in the same answer (`guess`).
    public static func guessPrompt(text: String) -> String {
        """
        This is text from a photo or a share. Decide whether it is a restaurant's menu, a book (its cover or back), or an event (a flyer, an invitation or a screenshot with a date). On the first line write "Kind: restaurant", "Kind: book" or "Kind: event", or "Kind: unsure" when it's none of these or you can't tell. Then, for that kind, \(leaveOut.prefix(1).lowercased() + leaveOut.dropFirst())

        For a restaurant:
        \(format(.restaurant)!)

        For a book:
        \(format(.book)!)

        For an event:
        \(format(.event)!)

        \(text)
        """
    }

    /// For Apple Intelligence: a long menu's later part (`chunks`), as menu lines only; the name and
    /// the other header lines come from the first part.
    public static func morePrompt(text: String) -> String {
        "This is more text from the same restaurant menu. Answer with only its menu, in exactly this format and nothing else: \(menuLines)\n\n\(text)"
    }

    // MARK: Several photos

    /// The line between photos' words, which Kinwall skips ("--- Page 2 ---").
    public static func pageLine(_ n: Int) -> String { "--- Page \(n) ---" }

    /// Several photos' words (or one) as one text, in the order shared, a page line between them.
    public static func joinPages(_ pages: [String]) -> String {
        pages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.enumerated()
            .map { $0.offset == 0 ? $0.element : "\(pageLine($0.offset + 1))\n\($0.element)" }.joined(separator: "\n")
    }

    /// How much text the on-device model takes in one go: its context is about 4,000 tokens for the
    /// prompt, the words and its answer together, and a menu's answer is about as long as its words.
    public static let pageLimit = 4000

    /// The joined words in parts of at most `limit` characters for the model: all of them when they
    /// fit, else whole pages together while they fit, and a page over the limit split between lines.
    public static func chunks(_ pages: [String], limit: Int = pageLimit) -> [String] {
        let joined = joinPages(pages)
        if joined.count <= limit { return joined.isEmpty ? [] : [joined] }
        let kept = pages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var pieces: [String] = []
        for (i, p) in kept.enumerated() {
            let page = i == 0 ? p : "\(pageLine(i + 1))\n\(p)"
            if page.count <= limit { pieces.append(page); continue }
            var part = ""
            for line in page.split(separator: "\n", omittingEmptySubsequences: false) {
                var line = Substring(line)
                while line.count > limit { // one line too long on its own: cut it
                    if !part.isEmpty { pieces.append(part); part = "" }
                    pieces.append(String(line.prefix(limit))); line = line.dropFirst(limit)
                }
                if part.isEmpty { part = String(line) } else if part.count + 1 + line.count <= limit { part += "\n" + line } else { pieces.append(part); part = String(line) }
            }
            if !part.isEmpty { pieces.append(part) }
        }
        var out: [String] = []
        for piece in pieces {
            if let last = out.last, last.count + 1 + piece.count <= limit { out[out.count - 1] = last + "\n" + piece } else { out.append(piece) }
        }
        return out
    }

    /// A line's value in the model's answer ("Name: Corner Slice" → "Corner Slice").
    static func value(_ label: String, in text: String) -> String? {
        text.split(whereSeparator: \.isNewline).lazy.compactMap { line -> String? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == label else { return nil }
            return parts[1].trimmingCharacters(in: .whitespaces).nilIfEmpty
        }.first
    }

    /// The model's answer to `guessPrompt`: its kind and the lines to send, or nil when it's unsure.
    public static func guess(_ answer: String) -> (kind: Kind, text: String)? {
        var lines = answer.replacingOccurrences(of: "**", with: "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        guard let first = lines.first, first.lowercased().hasPrefix("kind:"),
              let kind = Kind(rawValue: first.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased()), kind != .recipe else { return nil }
        let text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (kind, text)
    }

    /// The sheet's one line for a guess: "Looks like an event: Spring fair, Saturday, May 9", or for
    /// several photos of a menu "Looks like a menu: Corner Slice, 3 pages".
    public static func guessLine(_ kind: Kind, text: String, pages: Int = 1) -> String {
        func value(_ label: String) -> String? { Share.value(label, in: text).map { $0.count > 60 ? $0.prefix(59) + "…" : $0 } }
        let (what, detail): (String, String?) = switch kind {
        case .event: ("an event", [value("title"), value("date")].compactMap { $0 }.joined(separator: ", ").nilIfEmpty)
        case .book: ("a book", value("title"))
        case .restaurant, .recipe: ("a menu", [value("name"), pages > 1 ? "\(pages) pages" : nil].compactMap { $0 }.joined(separator: ", ").nilIfEmpty)
        }
        return "Looks like \(what)" + (detail.map { ": \($0)" } ?? "")
    }

    /// The small button under a guess: "Not an event?".
    public static func notLabel(_ kind: Kind) -> String {
        switch kind { case .event: "Not an event?"; case .book: "Not a book?"; case .restaurant, .recipe: "Not a menu?" }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#if canImport(Security)
/// The app's own sign-in, which the share sheet and Add to Kinwall use (POST /api/share is for
/// parents' devices): the OAuth tokens the app keeps in the shared Keychain group (src/oauth.ts,
/// refreshed and saved back here when they're about to lapse) or a paired device's key
/// (src/sharedKey.ts shareKey). Never the widgets' everyday key.
public enum AppSignIn {
    public struct SignInNeeded: Error {}

    /// src/oauth.ts's Tokens as the app saves them (expiresAt in ms).
    struct Tokens: Codable {
        var baseURL: URL; var clientId: String; var accessToken: String; var refreshToken: String; var expiresAt: Double; var scope: String
        var oauth: OAuth.Tokens {
            OAuth.Tokens(baseURL: baseURL, clientId: clientId, accessToken: accessToken, refreshToken: refreshToken,
                         expiresAt: Date(timeIntervalSince1970: expiresAt / 1000), scope: scope)
        }
        init(_ t: OAuth.Tokens) {
            baseURL = t.baseURL; clientId = t.clientId; accessToken = t.accessToken; refreshToken = t.refreshToken
            expiresAt = t.expiresAt.timeIntervalSince1970 * 1000; scope = t.scope
        }
    }

    private static func query(_ service: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "household"]
        if let group = SharedKeychain.group { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    private static func get(_ service: String) -> Data? {
        var q = query(service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    /// Saves it, adding the item when there's none: false when the Keychain turned it down.
    private static func write(_ service: String, _ data: Data) -> Bool {
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query(service) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query(service).merging(attrs) { $1 } as CFDictionary, nil) }
        return status == errSecSuccess
    }
    private static func savedTokens() -> Tokens? { get("family.kinwall.oauth").flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) } }

    /// The server and a key: the access token (refreshed first if it's about to lapse; refresh tokens
    /// rotate, so the new ones are saved before use), else the paired key. Nil when signed out.
    /// Callers at the same moment (an event's calendars and the event) share one read: two refreshes
    /// would race, and the loser's refresh token is already used, which signs the phone out. The app's
    /// own refresh (src/session.ts) runs apart from this one: see TokenRefresh for how they get along.
    public static func credential() async throws -> Connection? { try await OneAtATime.shared.credential() }

    private actor OneAtATime {
        static let shared = OneAtATime()
        private var running: Task<Connection?, Error>?
        func credential() async throws -> Connection? {
            if let running { return try await running.value }
            let task = Task { try await AppSignIn.readCredential() }
            running = task
            defer { running = nil }
            return try await task.value
        }
    }

    private static func readCredential() async throws -> Connection? {
        if let saved = savedTokens() {
            let t: OAuth.Tokens
            do {
                t = try await TokenRefresh.fresh(saved.oauth, reread: { savedTokens()?.oauth },
                                                 refresh: { try await OAuthClient(baseURL: $0.baseURL).refresh($0) },
                                                 save: { (try? JSONEncoder().encode(Tokens($0))).map { write("family.kinwall.oauth", $0) } ?? false })
            } catch let e as OAuthError where !e.code.hasPrefix("http_5") { throw SignInNeeded() } // the grant is gone
            return Connection(baseURL: t.baseURL, key: t.accessToken)
        }
        if let data = get("family.kinwall.share"), let c = try? JSONDecoder().decode(Connection.self, from: data) { return c }
        return nil
    }

    /// What to check, for the app to open when it next comes to the front (modules/kinwall-native
    /// PendingLink takes it): the share sheet can't open the app itself.
    public static func leaveForApp(_ link: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["link": link.absoluteString, "at": Date.now.timeIntervalSince1970]) else { return }
        _ = write("family.kinwall.link", data)
    }

    /// POSTs JSON to the family's server, signed in: the reply and its status, or nil when signed out.
    public static func post(_ path: String, json body: Data, timeout: TimeInterval) async throws -> (Data, Int)? {
        try await request(path, json: body, timeout: timeout)
    }

    /// GETs (no body) or POSTs JSON to the family's server, signed in: the reply and its status, or nil when signed out.
    public static func request(_ path: String, query: [URLQueryItem] = [], json body: Data? = nil, timeout: TimeInterval) async throws -> (Data, Int)? {
        guard let c = try await credential() else { return nil }
        let url = c.baseURL.appending(path: path)
        var req = URLRequest(url: query.isEmpty ? url : url.appending(queryItems: query), timeoutInterval: timeout)
        req.httpMethod = body == nil ? "GET" : "POST"
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        req.setValue("Bearer \(c.key)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

extension Share {
    /// Sends it to the family's Kinwall: the answer, or one line saying what went wrong.
    public static func send(_ request: Request) async -> Outcome {
        do {
            guard let (data, status) = try await AppSignIn.post("api/share", json: try JSONEncoder().encode(request), timeout: 60) else { return .failed(signInMessage) }
            return outcome(status: status, data: data)
        } catch is AppSignIn.SignInNeeded {
            return .failed(signInMessage)
        } catch {
            return .failed("Can't reach Kinwall. Check your connection and try again.")
        }
    }

    /// The calendars this phone can add an event to (`addable`), or nil when they can't be read.
    public static func calendars() async -> [FamilyCalendar]? {
        guard let (data, status) = try? await AppSignIn.request("api/calendars", timeout: 20), status == 200,
              let all = try? JSONDecoder().decode([FamilyCalendar].self, from: data) else { return nil }
        return addable(all)
    }
}
#endif
