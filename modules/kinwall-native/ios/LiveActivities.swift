import ActivityKit
import Foundation
import CryptoKit
import UIKit

/// The app's Live Activities (a cooking timer, a shopping trip, the next leave-by or start-prep
/// time, a medicine that's due), started, updated and ended from the web app's messages (src/liveActivities.ts, and
/// web/src/liveActivity.ts in the kinwall repo, which decides what they say). One of each kind at a
/// time. The deployment target is iOS 17, so ActivityKit and its interactive buttons are always
/// there; Live Activities turned off in Settings make all of this a no-op.
@MainActor public enum LiveActivities {
    typealias Attributes = KinwallActivityAttributes
    private static let eventWork = EventActivityCoordinator()

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
        if coalesced.contains(kind) {
            try await eventWork.perform { try await setActivity(kind: kind, json: json, colors: colors, onToken: onToken) }
        } else {
            try await setActivity(kind: kind, json: json, colors: colors, onToken: onToken)
        }
    }

    private static func setActivity(kind: String, json: String, colors: Attributes.Colors?, onToken: @escaping ([String: Any]) -> Void) async throws {
        if (kind == "medication" || kind == "event") && UIApplication.shared.applicationState != .active { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let (attributes, state, stale) = try content(kind: kind, json: json, colors: colors) else { return }
        if kind == "event", let key = attributes.activity, UserDefaults.standard.bool(forKey: "dismissed:" + key) { return }
        let next = ActivityContent(state: state, staleDate: stale)
        var current: Activity<Attributes>?
        for activity in onScreen(kind).sorted(by: { $0.id < $1.id }) {
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
        if kind == "event" { watchEventDismissal(activity) }
    }

    nonisolated private static func watchEventDismissal(_ activity: Activity<Attributes>) {
        Task { for await status in activity.activityStateUpdates where status == .dismissed {
            if let key = activity.attributes.activity { UserDefaults.standard.set(true, forKey: "dismissed:" + key) }
            return
        } }
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
        if (kind == "medication" || kind == "event") && UIApplication.shared.applicationState != .active { return }
        if coalesced.contains(kind) {
            try? await eventWork.perform { for activity in onScreen(kind) { await close(activity) } }
        } else {
            for activity in onScreen(kind) { await close(activity) }
        }
    }

    static func endAll() async {
        try? await eventWork.perform {
            for activity in Activity<Attributes>.activities { await close(activity) }
        }
    }

    /// Ones the page can't end because the app wasn't open: a leave-by past its end, a cooking
    /// timer that rang half an hour ago. Called when the app comes back and from background refresh.
    static func endStale(now: Date = .now) async {
        try? await eventWork.perform { await removeStale(now: now) }
    }

    private static func removeStale(now: Date) async {
        for activity in Activity<Attributes>.activities where activity.activityState == .active || activity.activityState == .stale {
            let a = activity.attributes, s = activity.content.state
            let over = (s.event.flatMap { date($0.endsAt) }.map { $0 <= now } ?? false) || (a.endsAt.map { $0 <= now } ?? false) || (a.kind == "cooking" && (s.date.map { $0.addingTimeInterval(30 * 60) <= now } ?? false))
            if over { await close(activity) }
        }
    }

    /// With push (a paid team): the push-to-start token, and each leave-by activity's update token
    /// (ones the server started too), for the app to register with the server.
    nonisolated static func watchPush(_ onToken: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in try? await eventWork.perform { for kind in coalesced { await coalesce(kind, preferred: nil) } } }
        guard pushEnabled else { return }
        if #available(iOS 17.2, *) {
            Task { for await data in Activity<Attributes>.pushToStartTokenUpdates { onToken(["kind": "start", "token": hex(data)]) } }
        }
        for activity in Activity<Attributes>.activities where activity.attributes.activity != nil { watchToken(activity, onToken) }
        Task { for await activity in Activity<Attributes>.activityUpdates where activity.attributes.activity != nil { watchToken(activity, onToken) } }
    }

    /// Kinds the server can start by push while the app shows one too.
    nonisolated static let coalesced: Set<String> = ["event", "medication"]

    /// Apple may start a card while the foreground app is creating one, or deliver the same card
    /// twice. Reconcile on arrival, not only when the web page next refreshes, and keep one
    /// deterministic live instance of the kind.
    private static func coalesce(_ kind: String, preferred: String?) async {
        let cards = onScreen(kind)
        let keep = EventActivityCoordinator.keeper(cards.map {
            .init(id: $0.id, activity: $0.attributes.activity, running: ($0.activityState == .active || $0.activityState == .stale) && !UserDefaults.standard.bool(forKey: "dismissed:" + ($0.attributes.activity ?? "")))
        }, preferred: preferred)
        for card in cards where card.id != keep { await close(card) }
    }

    nonisolated private static func watchToken(_ activity: Activity<Attributes>, _ onToken: @escaping ([String: Any]) -> Void) {
        let kind = activity.attributes.kind
        if kind == "event" { watchEventDismissal(activity) }
        if coalesced.contains(kind) {
            Task { @MainActor in try? await eventWork.perform { await coalesce(kind, preferred: activity.attributes.activity) } }
        }
        Task {
            for await data in activity.pushTokenUpdates {
                var token: [String: Any] = ["kind": "update", "token": hex(data), "activity": activity.attributes.activity ?? ""]
                if let ends = activity.attributes.endsAt { token["endsAt"] = ISO8601DateFormatter().string(from: ends) }
                if coalesced.contains(kind) {
                    let registered = token
                    try? await eventWork.perform {
                        await coalesce(kind, preferred: activity.attributes.activity)
                        // A duplicate's late token must never replace the survivor's server token.
                        if activity.activityState == .active || activity.activityState == .stale { onToken(registered) }
                    }
                } else { onToken(token) }
            }
        }
    }

    nonisolated private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    nonisolated private static func same(_ a: Attributes, _ b: Attributes) -> Bool {
        a.kind == b.kind && a.name == b.name && a.listId == b.listId && a.eventId == b.eventId && a.activity == b.activity && (a.kind == "event" || a.colors == b.colors) && a.dose == b.dose
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
    private struct Cooking: Decodable { let recipe: String; let timer: String; let step: String; let endsAt: Double; let done: Bool; let more: Int; let check: Check?; let timerId: Double?; let left: Double?; let nativeRevision: String? }
    private struct Check: Decodable { let at: Double }
    private struct Shopping: Decodable { let listId: String; let store: String; let left: Int; let next: Attributes.Entry?; let upcoming: [Attributes.Entry] }
    private struct Medication: Decodable { let medicationId: String; let date: String; let time: String; let label: String; let headline: String; let windowEndsAt: String; let stage: String; let named: Bool? }
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
            // Stale at its end, even for a range: the activity counts to the end and says when to check.
            return (Attributes(kind: "cooking", name: p.recipe, colors: colors), .init(title: p.timer, detail: p.step, date: p.left == nil ? ends : nil, count: p.more, done: p.done, check: p.left == nil ? check : nil, timerId: p.timerId, timerEnd: p.endsAt, left: p.left, nativeRevision: p.nativeRevision), p.done || p.left != nil ? nil : ends)
        case "shopping":
            let p = try decoder.decode(Shopping.self, from: data)
            return (Attributes(kind: "shopping", name: p.store, listId: p.listId, colors: colors), .init(title: p.next?.title ?? "", detail: p.next?.aisle, count: p.left, itemId: p.next?.id, queue: p.upcoming), nil)
        case "leaveBy":
            let p = try decoder.decode(LeaveBy.self, from: data)
            guard let at = date(p.at) else { return nil }
            let attributes = Attributes(kind: p.prep ? "prep" : "leave", name: p.title, eventId: p.eventId, activity: p.activity, endsAt: date(p.endsAt), colors: colors)
            return (attributes, .init(title: p.headline, detail: p.urgent, date: at), at)
        case "event":
            let p = try decoder.decode(Attributes.Event.self, from: data)
            guard let start = date(p.startsAt), let end = date(p.eventEndsAt), let until = date(p.endsAt) else { return nil }
            let lead = p.leadAt.flatMap { date($0) }
            let target = Date.now >= start ? end : lead.map { Date.now < $0 ? $0 : start } ?? start
            let headline = Date.now >= start ? "Ends in" : target == start ? "Starts in" : p.prep ? "Start prep in" : "Leave in"
            return (Attributes(kind: "event", name: "Event", eventId: p.eventId, activity: p.activity, colors: colors), .init(title: p.title, detail: headline, date: target, event: p), until)
        case "medication":
            // The label is the web app's own (generic unless the device opted into names): shown as is.
            let p = try decoder.decode(Medication.self, from: data)
            guard let until = date(p.windowEndsAt) else { return nil }
            let digest = SHA256.hash(data: Data("medication:\(p.medicationId):\(p.date):\(p.time):\(p.windowEndsAt)".utf8)).map { String(format: "%02x", $0) }.joined()
            let activity = "medication:\(digest):\(p.named == true ? "names" : "private")"
            let attributes = Attributes(kind: "medication", name: p.label, activity: activity, endsAt: until, colors: colors, dose: .init(medicationId: p.medicationId, date: p.date, time: p.time))
            return (attributes, .init(title: p.headline, detail: p.stage, date: until), until)
        default:
            return nil
        }
    }
}
