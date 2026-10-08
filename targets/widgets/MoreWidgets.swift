import AppIntents
import SwiftUI
import WidgetKit
import KinwallKit

// Take now (medicine due, Lock Screen and Home Screen) and the StandBy clock.

// MARK: - Take now

struct DosesEntry: TimelineEntry {
    let date: Date
    let doses: [DueDose]
    let members: [Member]
    /// The widget's setting and the server both allow names (a person's own device, or walls with names on).
    let showNames: Bool
    var signedOut = false
    var demo = false
    /// The family has medicines off (reminders off, or the Health tracker off).
    var off = false
    var hidden = FocusSettings.current()?.hideHealth == true
    /// Smart Stack: up top while a dose is due (never while hidden by a Focus).
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: doses.isEmpty || hidden ? 0 : 100) }

    func who(_ d: DueDose) -> String { members.first { $0.id == d.memberId }.map { "\($0.avatar.map { "\($0) " } ?? "")\($0.name)" } ?? "Someone" }
    /// "Amoxicillin 5 ml" with names allowed, else the generic "Medicine".
    func what(_ d: DueDose) -> String { showNames ? [d.name, d.dose].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty ?? "Medicine" : "Medicine" }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

struct TakeNowConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Take now"
    static let description = IntentDescription("Medicines due now. Names stay hidden unless you turn them on here, and even then only where Kinwall shares them with this device.")
    @Parameter(title: "Show medicine names", default: false) var showNames: Bool
}

struct DosesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DosesEntry { DosesEntry(date: .now, doses: DemoFamily.dueDoses().doses, members: DemoFamily.members, showNames: false) }
    func snapshot(for configuration: TakeNowConfig, in context: Context) async -> DosesEntry {
        context.isPreview ? placeholder(in: context) : await entry(configuration)
    }
    func timeline(for configuration: TakeNowConfig, in context: Context) async -> Timeline<DosesEntry> {
        // Doses come due on the hour or half hour, and snoozes last 10 minutes: look again every 15.
        Timeline(entries: [await entry(configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }
    private func entry(_ config: TakeNowConfig) async -> DosesEntry {
        guard let client = try? widgetClient() else {
            return Demo.isOn ? DosesEntry(date: .now, doses: DemoFamily.dueDoses().doses, members: DemoFamily.members, showNames: false, demo: true)
                : DosesEntry(date: .now, doses: [], members: [], showNames: false, signedOut: true)
        }
        async let on = client.medicinesOn()
        async let due = client.dueDoses() // 404 while the family has medicines off
        async let members = client.members()
        if await !on { return DosesEntry(date: .now, doses: [], members: [], showNames: false, off: true) }
        let d = try? await due
        return DosesEntry(date: .now, doses: d?.doses ?? [], members: (try? await members) ?? [], showNames: config.showNames && d?.names == true)
    }
}

struct TakeNowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TakeNow", intent: TakeNowConfig.self, provider: DosesProvider()) { entry in
            TakeNowView(entry: entry).modifier(DemoBadge(on: entry.demo)).modifier(FocusHidden(on: entry.hidden)).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Take now")
        .description("Medicines due now, with Taken. Names stay hidden unless you turn them on.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall])
    }
}

struct TakeNowView: View {
    let entry: DosesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let first = entry.doses.first
        switch family {
        case .accessoryInline:
            Text(first.map { "💊 \(entry.who($0)) · take now" } ?? (entry.off ? "💊 Off" : "💊 Nothing due"))
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "pills.fill").font(.caption)
                    Text(entry.off ? "Off" : "\(entry.doses.count)").font(entry.off ? .caption.weight(.bold) : .title3.weight(.bold)).widgetAccentable()
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let first {
                    Text("💊 Take now").font(.caption.weight(.semibold)).widgetAccentable()
                    Text(entry.who(first)).font(.headline).lineLimit(1)
                    Text(entry.doses.count > 1 ? "\(entry.what(first)) · +\(entry.doses.count - 1) more" : entry.what(first)).font(.caption).lineLimit(1).privacySensitive()
                } else {
                    Text("💊 Take now").font(.caption.weight(.semibold))
                    Text(entry.signedOut ? "Open Kinwall to sign in" : entry.off ? "Turned off in Kinwall" : "Nothing due").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            if entry.signedOut { ProblemView(problem: .signedOut) } else if entry.off { ProblemView(problem: .medicineOff) } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("💊 TAKE NOW").font(.caption.weight(.heavy)).foregroundStyle(Palette.accent)
                    if let first {
                        Text(entry.who(first)).font(.headline).lineLimit(1)
                        Text(entry.what(first)).font(.caption).foregroundStyle(.secondary).lineLimit(2).privacySensitive()
                        Spacer(minLength: 0)
                        if entry.demo {
                            Link(destination: URL(string: "family.kinwall.app:/open?to=calendar")!) { takenLabel }
                        } else {
                            Button(intent: MarkDoseIntent(medicationId: first.medicationId, date: first.date, time: first.time, action: "taken")) { takenLabel }.buttonStyle(.plain)
                        }
                        if entry.doses.count > 1 { Text("+\(entry.doses.count - 1) more").font(.caption2).foregroundStyle(.secondary) }
                    } else {
                        Text("Nothing due").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var takenLabel: some View {
        Label("Taken", systemImage: "checkmark").font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(Capsule().fill(Palette.accent.opacity(0.15)))
    }
}

/// Taken (or skipped, or snoozed) from a widget or the Watch's complication tap.
struct MarkDoseIntent: AppIntent {
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
        let dose = DueDose(medicationId: medicationId, memberId: "", date: date, time: time, dueAt: "", name: nil, dose: nil)
        try await widgetClient().mark(dose, KinwallClient.DoseAction(rawValue: action) ?? .taken)
        return .result()
    }
}

// MARK: - StandBy clock

/// A big clock with the next event under it, for StandBy (a charging iPhone on its side) and the
/// Home Screen. One entry a minute from a single fetch, so the clock keeps time between fetches.
struct ClockEntry: TimelineEntry {
    let date: Date
    let next: BoardEvent?
    var demo = false
}

struct ClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockEntry { ClockEntry(date: .now, next: Sample.board.nowAndNext(at: .now).next) }
    func getSnapshot(in context: Context, completion: @escaping (ClockEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion // WidgetKit's callbacks may be called from any thread
        Task {
            var board: Board?
            var demo = false
            if let client = try? widgetClient() { board = try? await client.board(days: 1) } else if Demo.isOn { board = Sample.board; demo = true }
            let start = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
            let entries = (0..<60).map { i -> ClockEntry in
                let at = start.addingTimeInterval(Double(i) * 60)
                return ClockEntry(date: at, next: board?.nowAndNext(at: at).next, demo: demo)
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

struct StandByClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StandByClock", provider: ClockProvider()) { entry in
            StandByClockView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Clock & next")
        .description("A big clock and what's next. Made for StandBy.")
        .supportedFamilies([.systemSmall])
    }
}

struct StandByClockView: View {
    let entry: ClockEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1).widgetAccentable()
            Text(entry.date, format: .dateTime.weekday(.wide).month().day()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let next = entry.next {
                Text(next.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let leave = next.leaveDate, leave > entry.date {
                    Text("🚗 leave by \(leave.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Palette.accent)
                } else {
                    Text(next.timeText).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing more today").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
