import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a Kinwall household lives and the key this device uses for it.
public struct Connection: Codable, Hashable, Sendable {
    public var baseURL: URL
    public var key: String
    public init(baseURL: URL, key: String) { self.baseURL = baseURL; self.key = key }
}

public struct APIError: Error, Equatable, LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public var errorDescription: String? { message }
    /// No answer at all (offline, server down). Stands in for URLError, whose NWPath App Intents
    /// can't send over XPC: an intent or entity query that threw one crashed the app.
    public static let unreachable = APIError(status: 0, message: "Can't reach Kinwall right now.")
    /// The server answered but didn't hand back what was added.
    public static let notSaved = APIError(status: 0, message: "Kinwall didn't save it. Try again in the app.")
}

/// Thin async client over Kinwall's REST API. Every call is one request; callers own caching.
public struct KinwallClient: Sendable {
    public let baseURL: URL
    private let key: String?
    private let session: URLSession

    public init(baseURL: URL, key: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.key = key
        self.session = session
    }
    public init(_ connection: Connection, session: URLSession = .shared) {
        self.init(baseURL: connection.baseURL, key: connection.key, session: session)
    }

    // MARK: Household

    public func settings() async throws -> Settings { try await send("GET", "api/settings") }
    /// The family's feature switches; all on when the server can't be asked (offline, older servers),
    /// since then there's nothing to hold back and the next call says what's wrong.
    public func features() async -> Features { (try? await settings())?.on ?? Features() }
    /// Settings.medicinesOn; on when the server can't be asked, like features().
    public func medicinesOn() async -> Bool { (try? await settings())?.medicinesOn ?? true }
    public func members() async throws -> [Member] { try await send("GET", "api/members") }
    /// A counter that goes up whenever anything in the household changes; poll it to know when to refresh.
    public func rev() async throws -> Int { try await send("GET", "api/rev", as: Rev.self).rev }

    /// Today and the next `days` days (default 7, max 14): events, open items, chores per person.
    public func board(days: Int = 7) async throws -> Board {
        try await send("GET", "api/board", query: [URLQueryItem(name: "days", value: String(days))])
    }

    // MARK: Device keys (widgets and the watch get their own everyday-access key)

    public struct DeviceKey: Codable, Sendable { public let id: String; public let key: String }
    public func createDeviceKey(name: String) async throws -> DeviceKey {
        try await send("POST", "api/device-keys", body: DeviceKeyBody(name: name))
    }
    /// Revokes the key this client uses (only works for an everyday-access device key).
    public func revokeOwnKey() async throws { try await sendIgnoringBody("DELETE", "api/device-keys/self") }

    // MARK: Chores

    /// `date` is YYYY-MM-DD in the household's timezone (see `HouseholdDate`).
    public func chores(on date: String) async throws -> [ChoreDay] {
        try await send("GET", "api/chores/day", query: [URLQueryItem(name: "date", value: date)])
    }
    /// `memberId`: who gets the points for an Anyone chore (nil = nobody in particular).
    /// Throws a 409 APIError while the chore's checklist has open items. True when it waits for a
    /// parent's OK (a display key ticking a chore that needs approval: no points yet).
    @discardableResult
    public func complete(chore id: String, on date: String, by memberId: String? = nil) async throws -> Bool {
        let data = try await perform(try request("POST", "api/chores/\(id)/complete", query: [], body: CompleteBody(date: date, memberId: memberId)))
        return (try? JSONDecoder().decode(Completed.self, from: data))?.pending == true
    }
    public func uncomplete(chore id: String, on date: String) async throws {
        try await sendIgnoringBody("DELETE", "api/chores/\(id)/complete", query: [URLQueryItem(name: "date", value: date)])
    }

    // MARK: Lists

    public func lists() async throws -> [FamilyList] { try await send("GET", "api/lists") }
    /// Event occurrences overlapping [from, to).
    public func events(from: Date, to: Date) async throws -> [EventInstance] {
        let iso = ISO8601DateFormatter()
        return try await send("GET", "api/events", query: [URLQueryItem(name: "from", value: iso.string(from: from)), URLQueryItem(name: "to", value: iso.string(from: to))])
    }
    public func list(_ id: String) async throws -> ListDetail { try await send("GET", "api/lists/\(id)") }
    @discardableResult
    public func addItems(_ titles: [String], to listId: String) async throws -> [ListItem] {
        try await send("POST", "api/lists/\(listId)/items", body: titles.map { NewItem(title: $0) })
    }
    /// One item, for Siri: returns it only once the server answered with it on that list, so the
    /// caller never says "Added" for a write that didn't happen (an empty or other-list answer).
    /// `skipExisting` (Siri): a name already on the list comes back instead of a second copy, with
    /// `existing` "open", or "reopened" when it was ticked (servers from 2026-09-30 on; older ones add).
    public func addItem(_ title: String, to listId: String, skipExisting: Bool = false) async throws -> ListItem {
        let query = skipExisting ? [URLQueryItem(name: "skipExisting", value: "1")] : []
        let added: [ListItem] = try await send("POST", "api/lists/\(listId)/items", query: query, body: [NewItem(title: title)])
        guard let item = added.first(where: { $0.listId == listId }) else { throw APIError.notSaved }
        return item
    }
    /// The groceries catalog: every item name the family has added before (GET /api/lists/remembered).
    public func remembered() async throws -> [RememberedItem] { try await send("GET", "api/lists/remembered") }
    public func setDone(_ done: Bool, item itemId: String, in listId: String) async throws {
        try await sendIgnoringBody("PATCH", "api/lists/\(listId)/items/\(itemId)", body: DoneBody(done: done))
    }

    // MARK: Medicines (404 while the family has them off)

    public func dueDoses() async throws -> DueDoses { try await send("GET", "api/medications/due") }
    public enum DoseAction: String, Encodable, Sendable { case taken, skipped, snooze }
    /// Taken, skipped, or snoozed 10 minutes (only while it's due).
    public func mark(_ dose: DueDose, _ action: DoseAction) async throws {
        try await sendIgnoringBody("POST", "api/medications/\(dose.medicationId)/doses", body: DoseBody(date: dose.date, time: dose.time, action: action))
    }

    // MARK: Pairing (no key needed)

    public func startPairing() async throws -> PairStart { try await send("POST", "api/pair", body: Empty()) }
    public func pollPairing(_ start: PairStart) async throws -> PairPoll {
        try await send("POST", "api/pair/poll", body: PollBody(pairingId: start.pairingId, pollToken: start.pollToken))
    }

    // MARK: Plumbing

    private struct Rev: Decodable { let rev: Int }
    private struct DeviceKeyBody: Encodable { let name: String }
    private struct Empty: Encodable {}
    private struct CompleteBody: Encodable { let date: String; let memberId: String? }
    private struct Completed: Decodable { let pending: Bool? }
    private struct NewItem: Encodable { let title: String }
    private struct DoneBody: Encodable { let done: Bool }
    private struct DoseBody: Encodable { let date: String; let time: String; let action: DoseAction }
    private struct PollBody: Encodable { let pairingId: String; let pollToken: String }
    private struct ErrorBody: Decodable { let error: String }

    private func request(_ method: String, _ path: String, query: [URLQueryItem], body: (any Encodable)?) throws -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch is URLError { throw APIError.unreachable }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw APIError(status: status, message: message)
        }
        return data
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil, as: T.Type = T.self) async throws -> T {
        let data = try await perform(try request(method, path, query: query, body: body))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func sendIgnoringBody(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws {
        _ = try await perform(try request(method, path, query: query, body: body))
    }
}
