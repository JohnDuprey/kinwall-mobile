import Foundation

/// Device-local timer controls. The web page acknowledges an override by echoing its revision;
/// until then even an old "done" payload cannot overwrite a native pause or resumed deadline.
struct CookingTimerState: Codable {
    struct Timer: Codable {
        var id: Double
        var label: String
        var seconds: Double
        var endsAt: Double
        var done: Bool
        var left: Double?
        var title: String?
        var detail: String?
        var check: Double?
        var nativeRevision: String?
        var alarmTitle: String
        var alarmBody: String
        var checkTitle: String?
        var name: String { String(label.components(separatedBy: " · ")[0]) }
    }
    var timers: [Timer] = []
    private var overrides: [String: Timer] = [:]
    var changes: [Timer] { Array(overrides.values) }

    mutating func receive(_ data: Data) throws {
        struct Payload: Decodable { var timers: [Timer] }
        let incoming = try JSONDecoder().decode(Payload.self, from: data).timers
        overrides = overrides.filter { key, _ in incoming.contains { String($0.id) == key } }
        let previous = timers
        timers = incoming.map { timer in
            let key = String(timer.id)
            // Even after acknowledgment, a delayed older bridge call must not undo the
            // accepted revision. In-page actions preserve that revision when they edit time.
            if overrides[key] == nil, let current = previous.first(where: { $0.id == timer.id }),
               current.nativeRevision != nil, timer.nativeRevision != current.nativeRevision {
                overrides[key] = current
            }
            guard let changed = overrides[key] else { return timer }
            if timer.nativeRevision == changed.nativeRevision { overrides.removeValue(forKey: key); return timer }
            var result = timer
            result.endsAt = changed.endsAt; result.left = changed.left
            result.done = false; result.nativeRevision = changed.nativeRevision
            return result
        }
    }

    /// Explicit desired state plus version makes delayed or double taps harmless. The button's
    /// deadline comes back through App Intents, which doesn't keep a fractional Double bit for bit,
    /// so it matches within a millisecond; the revision still rejects stale buttons.
    mutating func change(id: Double, start: Bool, expectedEnd: Double, expectedRevision: String, now: Double) -> Bool {
        let now = now.rounded()
        guard let i = timers.firstIndex(where: { $0.id == id }), !timers[i].done,
              abs(timers[i].endsAt - expectedEnd) < 1, (timers[i].nativeRevision ?? "") == expectedRevision else { return false }
        if start {
            guard let left = timers[i].left, left > 0 else { return false }
            timers[i].endsAt = now + left; timers[i].left = nil
        } else {
            guard timers[i].left == nil, timers[i].endsAt > now else { return false }
            timers[i].left = timers[i].endsAt - now
        }
        timers[i].nativeRevision = UUID().uuidString
        overrides[String(id)] = timers[i]
        return true
    }

    /// Same choice as web/src/liveActivity.ts: paused first so Start remains reachable, then
    /// the soonest running timer, then the last one that rang. Alarm dates remain absolute ms.
    func payload() throws -> Data {
        let running = timers.filter { !$0.done && $0.left == nil }.sorted { $0.endsAt < $1.endsAt }
        guard let shown = timers.first(where: { !$0.done && $0.left != nil }) ?? running.first ?? timers.sorted(by: { $0.endsAt > $1.endsAt }).first else {
            return Data("{}".utf8)
        }
        func alarm(_ timer: Timer, check: Bool = false) -> [String: Any] {
            ["at": timer.endsAt - (check ? (timer.seconds - (timer.check ?? timer.seconds)) * 1000 : 0),
             "title": check ? (timer.checkTitle ?? timer.alarmTitle) : timer.alarmTitle, "body": timer.alarmBody]
        }
        var p: [String: Any] = ["recipe": shown.title ?? "Timer", "timer": shown.name,
            "step": shown.detail ?? "", "endsAt": shown.endsAt, "done": shown.done,
            "more": running.filter { $0.id != shown.id }.count, "timerId": shown.id,
            "alarms": running.map { alarm($0) }, "checks": running.filter { $0.check != nil }.map { alarm($0, check: true) }]
        if let left = shown.left { p["left"] = left }
        if let revision = shown.nativeRevision { p["nativeRevision"] = revision }
        if let check = shown.check { p["check"] = ["at": shown.endsAt - (shown.seconds - check) * 1000] }
        return try JSONSerialization.data(withJSONObject: p)
    }

    static let key = "kinwall.cookingTimerControls.v1"
    static func load() -> Self { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self() }
    func save() throws { UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.key) }
}
