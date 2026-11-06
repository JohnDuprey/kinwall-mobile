import Foundation

/// Intents run in the app process. Serialize the entire alarm/activity update with incoming web
/// payloads; persistence survives a background launch and requires no App Group entitlement.
@MainActor public enum CookingTimerControls {
    private static let work = EventActivityCoordinator()
    nonisolated public static let changed = Notification.Name("KinwallCookingTimerChanged")
    private static var colors: KinwallActivityAttributes.Colors? {
        get { UserDefaults.standard.data(forKey: "cookingTimerColors").flatMap { try? JSONDecoder().decode(KinwallActivityAttributes.Colors.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "cookingTimerColors") }
    }
    nonisolated public static func changes() -> String {
        (try? String(data: JSONEncoder().encode(CookingTimerState.load().changes), encoding: .utf8)) ?? "[]"
    }
    static func set(json: String, colors: KinwallActivityAttributes.Colors?) async throws {
        try await work.perform {
            Self.colors = colors
            var state = CookingTimerState.load()
            // Older pages keep their existing activity and alarms, without a control button.
            if (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["timers"] == nil {
                UserDefaults.standard.removeObject(forKey: CookingTimerState.key)
                try await apply(json, colors: colors)
                return
            }
            try state.receive(Data(json.utf8)); try state.save()
            try await apply(String(decoding: state.payload(), as: UTF8.self), colors: colors)
        }
    }
    public static func change(id: Double, start: Bool, expectedEnd: Double, expectedRevision: String) async throws {
        try await work.perform {
            var state = CookingTimerState.load()
            guard state.change(id: id, start: start, expectedEnd: expectedEnd, expectedRevision: expectedRevision, now: Date.now.timeIntervalSince1970 * 1000) else { return }
            try state.save()
            try await apply(String(decoding: state.payload(), as: UTF8.self), colors: colors)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
    static func clear() async throws {
        try await work.perform {
            UserDefaults.standard.removeObject(forKey: CookingTimerState.key)
            colors = nil
            await CookingAlarms.clear()
            await LiveActivities.end(kind: "cooking")
        }
    }
    private static func apply(_ json: String, colors: KinwallActivityAttributes.Colors?) async throws {
        await CookingAlarms.set(json: json, accent: colors?.accent)
        try await LiveActivities.set(kind: "cooking", json: json, colors: colors) { _ in }
    }
}
