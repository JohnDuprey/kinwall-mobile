import ActivityKit
import AppIntents
import KinwallKit
#if canImport(KinwallNative)
internal import KinwallNative // the app: KinwallActivityAttributes comes from the native module
#endif

// "Got it" on the shopping trip's Live Activity, and Taken / Snooze on a medicine's (below) (targets/widgets/LiveActivities.swift). Compiled into
// the app and the widget extension (plugins/withKinwallNative.js): the button needs the type there,
// and iOS may run it in either process (in the iOS 27 Simulator it runs in the extension, which can
// update the activity too), so both copies do the whole job.
//
// It ticks the item with the widgets' own everyday-access key from the shared Keychain group
// (KinwallKit SharedKeychain), which a free Personal Team signs, so no App Group and no waiting
// for the app's page. Then it moves the activity on to the next item it carries (up to five; the
// page sends a fresh list when it's next open). Signed out, it fails and Open is the way in.

struct GotItIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Got it"
    static let isDiscoverable = false
    @Parameter(title: "List") var listId: String
    @Parameter(title: "Item") var itemId: String
    init() {}
    init(listId: String, itemId: String) { self.listId = listId; self.itemId = itemId }

    func perform() async throws -> some IntentResult {
        if let connection = try? SharedKeychain.widgetStore.load() {
            try await KinwallClient(connection).setDone(true, item: itemId, in: listId)
        } else if (try? SharedKeychain.demoStore.load()) == nil {
            throw GotItError.signedOut
        } // the demo: its sample list just moves on
        for activity in Activity<KinwallActivityAttributes>.activities where activity.attributes.kind == "shopping" && activity.content.state.itemId == itemId { // listId may be the other list's
            var s = activity.content.state
            let rest = Array((s.queue ?? []).drop { $0.id != itemId }.dropFirst())
            s.count = max(0, s.count - 1)
            s.itemId = rest.first?.id
            s.title = rest.first?.title ?? ""
            s.detail = rest.first?.aisle
            s.queue = rest
            await activity.update(ActivityContent(state: s, staleDate: nil))
        }
        return .result()
    }
}

enum GotItError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    var localizedStringResource: LocalizedStringResource { "Open Kinwall to sign in first." }
}

// Taken and Snooze on the medicine Live Activity (targets/widgets/LiveActivities.swift): the dose is
// marked with the widgets' key, which belongs to the device's person, so the server lets a person's
// own phone mark only theirs. Both end the activity; the web app starts it again when a snooze runs out.
struct MarkDoseActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark a dose"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = false
    @Parameter(title: "Medicine") var medicationId: String
    @Parameter(title: "Date") var date: String
    @Parameter(title: "Time") var time: String
    @Parameter(title: "Action") var action: String
    init() {}
    init(medicationId: String, date: String, time: String, action: String) { self.medicationId = medicationId; self.date = date; self.time = time; self.action = action }

    func perform() async throws -> some IntentResult {
        if let connection = try? SharedKeychain.widgetStore.load() {
            let dose = DueDose(medicationId: medicationId, memberId: "", date: date, time: time, dueAt: "", name: nil, dose: nil)
            try await KinwallClient(connection).mark(dose, action == "snooze" ? .snooze : .taken)
        } else if (try? SharedKeychain.demoStore.load()) == nil {
            throw GotItError.signedOut
        } // the demo: nothing to save
        // Either way it goes: Taken is done, and after a snooze the web app starts it again when it's due.
        for activity in Activity<KinwallActivityAttributes>.activities where activity.attributes.dose == .init(medicationId: medicationId, date: date, time: time) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}

#if canImport(KinwallNative)
// Stop on a cooking timer's alarm (iOS 26 AlarmKit, modules/kinwall-native CookingAlarms.swift):
// iOS runs it in the app, even while it's closed, so the timer's Live Activity goes with the alarm
// instead of waiting for the page. App only: AlarmKit runs a stop intent in the app's process.
struct StopCookingTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop a cooking timer"
    static let isDiscoverable = false
    @Parameter(title: "Finish") var at: Double
    init() {}
    init(at: Double) { self.at = at }

    func perform() async throws -> some IntentResult {
        await LiveActivities.timerStopped(at: at)
        return .result()
    }
}
#endif
