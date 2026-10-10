import ActivityKit
import Foundation

/// The app's Live Activities (a cooking timer, a shopping trip, the next leave-by or start-prep
/// time, a medicine that's due), started, updated and ended from the web app's messages (src/liveActivities.ts, and
/// web/src/liveActivity.ts in the kinwall repo, which decides what they say). One of each kind at a
/// time. The deployment target is iOS 17, so ActivityKit and its interactive buttons are always
/// there; Live Activities turned off in Settings make all of this a no-op.
@MainActor public enum LiveActivities {
    typealias Attributes = KinwallActivityAttributes

    /// Apple push is only signed in with a paid team: the plugin sets KinwallPush when a build has
    /// the push entitlement (KINWALL_PUSH=1 at prebuild, docs/PLAN.md). Without it no tokens are asked for.
    nonisolated static var pushEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "KinwallPush") as? Bool ?? false }

    /// The web app's kind ("leaveBy") and the attributes' ("leave" or "prep").
    nonisolated static func group(_ kind: String) -> Set<String> { kind == "leaveBy" ? ["leave", "prep"] : [kind] }
    /// The kind's activities still on screen. A stale one (past its stale date: a timer that's up, a
    /// leave-by time that came) is still there too, as is an ended one waiting out its dismissal
    /// policy, so ending or replacing the kind ends them as well.
    static func onScreen(_ kind: String) -> [Activity<Attributes>] {
        Activity<Attributes>.activities.filter { group(kind).contains($0.attributes.kind) && $0.activityState != .dismissed }
    }

    /// Cooking timers (their finishes, ms since 1970) whose activity the person took away: swiped
    /// off the Lock Screen, or Stop on the timer's alarm. A later payload with only these (the page
    /// catching up: "Done: Rice") doesn't bring it back; a timer that's new, or paused and resumed, does.
    private static var seenOff = Set<Double>()
    /// The timers in the last cooking payload: the ones a swiped-away activity was about.
    private static var lastTimers = Set<Double>()
    /// Activities the app ended itself, so their end isn't taken for a swipe.
    private static var endedHere = Set<String>()
    /// A timer that rang stays on the Lock Screen as "Done: Rice" this long, then iOS takes it away,
    /// even if cooking mode is never opened again.
    static let doneFor: TimeInterval = 5 * 60

    private static func close(_ activity: Activity<Attributes>, _ content: ActivityContent<Attributes.ContentState>? = nil, after: Date? = nil) async {
        endedHere.insert(activity.id)
        await activity.end(content, dismissalPolicy: after.map { .after($0) } ?? .immediate)
    }

    /// Starts the kind's activity, or updates the one showing. What an activity is about (its
    /// attributes) can't change, so another recipe, store or event ends the old one first.
    static func set(kind: String, json: String, colors: Attributes.Colors?, onToken: @escaping ([String: Any]) -> Void) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let (attributes, state, stale) = try content(kind: kind, json: json, colors: colors) else { return }
        let next = ActivityContent(state: state, staleDate: stale)
        var current: Activity<Attributes>?
        for activity in onScreen(kind) {
            if current == nil, activity.activityState != .ended, same(activity.attributes, attributes) { current = activity }
            else { await close(activity) }
        }
        if kind == "cooking" {
            let timers = cookingTimers(json)
            lastTimers = timers
            // Rang: it says "Done" on the Lock Screen for a few minutes and goes, out of the Dynamic
            // Island now. Never started just to say so.
            if state.done { if let current { await close(current, next, after: .now.addingTimeInterval(doneFor)) }; return }
            if current == nil && timers.isSubset(of: seenOff) { return }
        }
        if let current { await current.update(next); return }
        let push = pushEnabled && attributes.activity != nil
        let activity = try Activity.request(attributes: attributes, content: next, pushType: push ? .token : nil)
        if push { watchToken(activity, onToken) }
        if kind == "cooking" { watchSwipe(activity) }
    }

    /// A cooking activity the person swiped away: its timers aren't shown again.
    private static func watchSwipe(_ activity: Activity<Attributes>) {
        Task {
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                if endedHere.remove(activity.id) == nil { seenOff.formUnion(lastTimers) }
                return
            }
        }
    }

    /// Stop on a cooking timer's alarm (CookingAlarms: its stop intent, which iOS runs in the app even
    /// while it's closed): the activity showing that timer goes now, and doesn't come back when the
    /// page next says it's done. `at`: the timer's finish, ms since 1970.
    public static func timerStopped(at: Double) async {
        seenOff.insert(at)
        for activity in onScreen("cooking") where activity.content.state.date.map({ abs($0.timeIntervalSince1970 * 1000 - at) < 1000 }) ?? false {
            await close(activity)
        }
    }

    static func end(kind: String) async {
        for activity in onScreen(kind) { await close(activity) }
    }

    static func endAll() async {
        for activity in Activity<Attributes>.activities { await close(activity) }
    }

    /// Ones the page can't end because the app wasn't open: a leave-by past its end, a cooking
    /// timer that rang half an hour ago. Called when the app comes back and from background refresh.
    static func endStale(now: Date = .now) async {
        for activity in Activity<Attributes>.activities where activity.activityState == .active || activity.activityState == .stale {
            let a = activity.attributes, s = activity.content.state
            let over = (a.endsAt.map { $0 <= now } ?? false) || (a.kind == "cooking" && (s.date.map { $0.addingTimeInterval(30 * 60) <= now } ?? false))
            if over { await close(activity) }
        }
    }

    /// With push (a paid team): the push-to-start token, and each leave-by activity's update token
    /// (ones the server started too), for the app to register with the server.
    nonisolated static func watchPush(_ onToken: @escaping ([String: Any]) -> Void) {
        guard pushEnabled else { return }
        if #available(iOS 17.2, *) {
            Task { for await data in Activity<Attributes>.pushToStartTokenUpdates { onToken(["kind": "start", "token": hex(data)]) } }
        }
        Task { for await activity in Activity<Attributes>.activityUpdates where activity.attributes.activity != nil { watchToken(activity, onToken) } }
    }

    nonisolated private static func watchToken(_ activity: Activity<Attributes>, _ onToken: @escaping ([String: Any]) -> Void) {
        Task {
            for await data in activity.pushTokenUpdates {
                var token: [String: Any] = ["kind": "update", "token": hex(data), "activity": activity.attributes.activity ?? ""]
                if let ends = activity.attributes.endsAt { token["endsAt"] = ISO8601DateFormatter().string(from: ends) }
                onToken(token)
            }
        }
    }

    nonisolated private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    nonisolated private static func same(_ a: Attributes, _ b: Attributes) -> Bool {
        a.kind == b.kind && a.name == b.name && a.listId == b.listId && a.eventId == b.eventId && a.activity == b.activity && a.colors == b.colors && a.dose == b.dose
    }

    // MARK: - The web app's payloads (web/src/liveActivity.ts)

    private struct At: Decodable { let at: Double }
    private struct CookingTimers: Decodable { let endsAt: Double; let alarms: [At]? }
    /// The timer shown and every running one's finish.
    nonisolated private static func cookingTimers(_ json: String) -> Set<Double> {
        guard let p = try? JSONDecoder().decode(CookingTimers.self, from: Data(json.utf8)) else { return [] }
        return Set([p.endsAt] + (p.alarms ?? []).map(\.at))
    }
    /// `check`: a range's (web/src/liveActivity.ts); absent for a single time and from older pages.
    private struct Cooking: Decodable { let recipe: String; let timer: String; let step: String; let endsAt: Double; let done: Bool; let more: Int; let check: Check? }
    private struct Check: Decodable { let at: Double; let before: String; let after: String }
    private struct Shopping: Decodable { let listId: String; let store: String; let left: Int; let next: Attributes.Entry?; let upcoming: [Attributes.Entry] }
    private struct Medication: Decodable { let medicationId: String; let date: String; let time: String; let label: String; let headline: String; let windowEndsAt: String; let stage: String }
    private struct LeaveBy: Decodable { let activity: String; let eventId: String; let title: String; let prep: Bool; let at: String; let endsAt: String; let headline: String; let urgent: String }

    nonisolated private static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    nonisolated static func content(kind: String, json: String, colors: Attributes.Colors?) throws -> (Attributes, Attributes.ContentState, Date?)? {
        let data = Data(json.utf8), decoder = JSONDecoder()
        switch kind {
        case "cooking":
            let p = try decoder.decode(Cooking.self, from: data)
            let ends = Date(timeIntervalSince1970: p.endsAt / 1000), check = p.check.map { Date(timeIntervalSince1970: $0.at / 1000) }
            // A range goes stale at its check first, so the Lock Screen redraws there and moves on to its end.
            let stale = p.done ? nil : check.flatMap { $0 > .now ? $0 : nil } ?? ends
            return (Attributes(kind: "cooking", name: p.recipe, colors: colors), .init(title: p.timer, detail: p.step, date: ends, count: p.more, done: p.done, check: check, beforeCheck: p.check?.before, afterCheck: p.check?.after), stale)
        case "shopping":
            let p = try decoder.decode(Shopping.self, from: data)
            return (Attributes(kind: "shopping", name: p.store, listId: p.listId, colors: colors), .init(title: p.next?.title ?? "", detail: p.next?.aisle, count: p.left, itemId: p.next?.id, queue: p.upcoming), nil)
        case "leaveBy":
            let p = try decoder.decode(LeaveBy.self, from: data)
            guard let at = date(p.at) else { return nil }
            let attributes = Attributes(kind: p.prep ? "prep" : "leave", name: p.title, eventId: p.eventId, activity: p.activity, endsAt: date(p.endsAt), colors: colors)
            return (attributes, .init(title: p.headline, detail: p.urgent, date: at), at)
        case "medication":
            // The label is the web app's own (generic unless the device opted into names): shown as is.
            let p = try decoder.decode(Medication.self, from: data)
            guard let until = date(p.windowEndsAt) else { return nil }
            let attributes = Attributes(kind: "medication", name: p.label, endsAt: until, colors: colors, dose: .init(medicationId: p.medicationId, date: p.date, time: p.time))
            return (attributes, .init(title: p.headline, detail: p.stage, date: until), until)
        default:
            return nil
        }
    }
}
