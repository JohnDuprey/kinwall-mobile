import AppIntents
import SwiftUI
import WidgetKit
import KinwallKit

// Watch complications (docs/WIDGETS-AND-WATCH.md): Next event with the leave-by countdown,
// Chores left as a gauge, and Take now (how many medicines are due). They read the Board with the Watch's key, which the Watch app keeps in
// the shared Keychain group (SharedKeychain.widgetStore). Next event and Take now set a relevance, so the
// Smart Stack brings them up before a leave-by time and while a dose is due.

@main
struct KinwallComplications: WidgetBundle {
    var body: some Widget {
        NextEventComplication()
        ChoresLeftComplication()
        MedsDueComplication()
        BatteryComplication()
    }
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: Board?
    /// The family turned chores off (the board then has none).
    var choresOff = false
    var next: BoardEvent? {
        guard let board else { return nil }
        let (now, next) = board.nowAndNext(at: date)
        return next ?? now
    }
    var choresLeft: (remaining: Int, total: Int) {
        (board?.chores.reduce(0) { $0 + $1.remaining } ?? 0, board?.chores.reduce(0) { $0 + $1.total } ?? 0)
    }
    /// The Smart Stack: rises over the hour before the next leave-by time (or start).
    var relevance: TimelineEntryRelevance? {
        guard let e = board?.nowAndNext(at: date).next, let at = e.leaveDate ?? e.startDate else { return nil }
        return TimelineEntryRelevance(score: Float(max(0, 60 - at.timeIntervalSince(date) / 60)))
    }
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry { BoardEntry(date: .now, board: nil) }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        nonisolated(unsafe) let completion = completion // WidgetKit's callbacks may be called from any thread
        Task { completion(await load().first ?? BoardEntry(date: .now, board: nil)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task { completion(Timeline(entries: await load(), policy: .after(.now.addingTimeInterval(30 * 60)))) }
    }

    /// One fetch, then an entry whenever an event today starts or ends, so "next" rolls over on time.
    private func load() async -> [BoardEntry] {
        guard let connection = try? SharedKeychain.widgetStore.load() else { return [BoardEntry(date: .now, board: nil)] }
        let client = KinwallClient(connection)
        async let on = client.features()
        guard let fetched = try? await client.board(days: 1) else { return [BoardEntry(date: .now, board: nil)] }
        let features = await on
        let board = fetched.respecting(features)
        let now = Date.now
        let changes = board.events.filter { !$0.allDay }.flatMap { [$0.startDate, $0.endDate, $0.leaveDate, ($0.leaveDate ?? $0.startDate)?.addingTimeInterval(-30 * 60)] }.compactMap { $0 }
            .filter { $0 > now && $0 < now.addingTimeInterval(30 * 60) }
        return ([now] + Set(changes).sorted()).map { BoardEntry(date: $0, board: board, choresOff: !features.chores) }
    }
}

// MARK: - Next event

struct NextEventComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextEvent", provider: BoardProvider()) { entry in
            NextEventView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next event")
        .description("What's next, and when to leave.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NextEventView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let e = entry.next
        switch family {
        case .accessoryInline:
            Text(e.map { "\($0.title) · \(time($0))" } ?? "Nothing more today")
        case .accessoryCorner:
            Image(systemName: "calendar")
                .widgetLabel { Text(e.map { "\($0.title) \(time($0))" } ?? "Free") }
        default:
            VStack(alignment: .leading, spacing: 1) {
                if let e {
                    Text(e.title).font(.headline).widgetAccentable().lineLimit(1)
                    Text(time(e)).font(.caption)
                    if let leave = e.leaveDate, leave > entry.date {
                        Text("🚗 leave in \(leave, style: .timer)").font(.caption).monospacedDigit()
                    }
                } else {
                    Text("Nothing more today").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func time(_ e: BoardEvent) -> String {
        guard let start = e.startDate else { return "All day" }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Chores left

struct ChoresLeftComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChoresLeft", provider: BoardProvider()) { entry in
            let c = entry.choresLeft
            Gauge(value: Double(c.total - c.remaining), in: 0...Double(max(c.total, 1))) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text(entry.choresOff ? "Off" : c.total == 0 ? "–" : "\(c.remaining)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Chores left")
        .description("A ring that fills as the family's chores get done.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Meds due

/// How many doses are due now, never which medicines: a watch face is on show.
struct MedsEntry: TimelineEntry {
    let date: Date; let doses: [DueDose]?
    var count: Int? { doses?.count }
    /// The family has medicines off (reminders off, or the Health tracker off).
    var off = false
    /// The Smart Stack: up top while a dose is due.
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: (count ?? 0) > 0 ? 100 : 0) }
}

struct MedsProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedsEntry { MedsEntry(date: .now, doses: DemoFamily.dueDoses().doses) }
    func getSnapshot(in context: Context, completion: @escaping (MedsEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(await load()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MedsEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task { completion(Timeline(entries: [await load()], policy: .after(.now.addingTimeInterval(15 * 60)))) }
    }
    private func load() async -> MedsEntry {
        guard let connection = try? SharedKeychain.widgetStore.load() else { return MedsEntry(date: .now, doses: nil) }
        let client = KinwallClient(connection)
        let off = await !client.medicinesOn()
        let doses = off ? [] : (try? await client.dueDoses())?.doses.map(\.withoutMedicineNames)
        return MedsEntry(date: .now, doses: doses, off: off)
    }
}

struct MedsDueComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MedsDue", provider: MedsProvider()) { entry in
            MedsDueView(entry: entry).widgetURL(WatchDestination.medicinesURL).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Take now")
        .description("Medicines due, with Taken and Snooze in the Smart Stack. Names stay off the watch face.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct MedsDueView: View {
    let entry: MedsEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let n = entry.count ?? 0
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.off ? "💊 Medicine is off" : entry.count == nil ? "💊 Open Take now to refresh" : n == 0 ? "💊 Nothing due" : "💊 \(n) due")
                    Spacer(minLength: 2)
                    if let at = entry.doses?.first?.dueDate {
                        Text(at, style: .time)
                    }
                }.font(.caption.weight(.semibold)).lineLimit(1)
                if let dose = entry.doses?.first {
                    HStack(spacing: 6) {
                        Button(intent: WatchMarkDoseIntent(dose: dose, action: "taken")) {
                            Text("Taken").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Button(intent: WatchMarkDoseIntent(dose: dose, action: "snooze")) {
                            Text("Snooze").frame(maxWidth: .infinity, minHeight: 44)
                        }.accessibilityLabel("Snooze 10 minutes")
                    }.buttonStyle(.bordered).font(.caption)
                }
            }
        case .accessoryInline: Text(entry.off ? "💊 Off" : entry.count == nil ? "💊 Open Take now" : n == 0 ? "💊 Nothing due" : "💊 \(n) due")
        case .accessoryCorner: Image(systemName: "pills.fill").widgetLabel { Text(entry.off ? "Off" : entry.count == nil ? "Open Take now" : n == 0 ? "None due" : "\(n) due") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "pills.fill").font(.caption)
                    Text(entry.off ? "Off" : entry.count == nil ? "–" : "\(n)").font(entry.off ? .caption.weight(.bold) : .title3.weight(.bold)).widgetAccentable()
                }
            }
        }
    }
}

/// Runs on the Watch with its own person-scoped key; a failed save leaves the dose visible.
struct WatchMarkDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a dose"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = false
    @Parameter(title: "Medicine") var medicationId: String
    @Parameter(title: "Date") var date: String
    @Parameter(title: "Time") var time: String
    @Parameter(title: "Action") var action: String
    init() {}
    init(dose: DueDose, action: String) {
        medicationId = dose.medicationId; date = dose.date; time = dose.time; self.action = action
    }
    func perform() async throws -> some IntentResult {
        guard let connection = try SharedKeychain.widgetStore.load() else { throw WatchMedicineError.signedOut }
        let dose = DueDose(medicationId: medicationId, memberId: "", date: date, time: time, dueAt: "", name: nil, dose: nil)
        try await KinwallClient(connection).mark(dose, action == "snooze" ? .snooze : .taken)
        WidgetCenter.shared.reloadTimelines(ofKind: "MedsDue")
        return .result()
    }
}
enum WatchMedicineError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    var localizedStringResource: LocalizedStringResource { "Open Kinwall on your iPhone to connect this Watch." }
}

// MARK: - Energy battery

/// The owner's energy battery as a gauge only: no reasons, no name (a watch face is on show).
/// Only on a person's own Watch; the server refuses anyone else.
struct BatteryLevelEntry: TimelineEntry {
    let date: Date; let level: Int?
    /// The family turned check-ins off (the battery comes from them).
    var off = false
}

struct BatteryLevelProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryLevelEntry { BatteryLevelEntry(date: .now, level: 62) }
    func getSnapshot(in context: Context, completion: @escaping (BatteryLevelEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryLevelEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            var level: Int?
            var off = false
            if let connection = try? SharedKeychain.widgetStore.load() {
                let client = KinwallClient(connection)
                off = await !client.features().checkIns
                if !off, let person = try? await client.me().person { level = (try? await client.battery(person))?.summary?.level }
            }
            completion(Timeline(entries: [BatteryLevelEntry(date: .now, level: level, off: off)], policy: .after(.now.addingTimeInterval(3 * 3600))))
        }
    }
}

struct BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Battery", provider: BatteryLevelProvider()) { entry in
            Gauge(value: Double(entry.level ?? 0), in: 0...100) { Image(systemName: "bolt.fill") } currentValueLabel: { Text(entry.level.map { "\($0)" } ?? (entry.off ? "Off" : "–")) }
                .gaugeStyle(.accessoryCircularCapacity)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Energy")
        .description("Your energy battery as a gauge. Only on your own Watch.")
        .supportedFamilies([.accessoryCircular])
    }
}
