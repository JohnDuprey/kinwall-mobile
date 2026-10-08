import AppIntents
import SwiftUI
import WidgetKit
import KinwallKit

// The daily check-in and the energy battery. Health data (kinwall AGENTS.md): read only with a
// key that belongs to the person, since the widgets' key inherits the owner of the app's sign-in
// (Settings → Access → "Who uses it"). A shared wall's key gets "Only on a person's own device",
// and the server refuses anyone else's answers anyway. Answers go straight to the server; nothing
// is cached beyond the timeline entry on show, and text is marked privacy-sensitive so a locked
// device redacts it.

/// Whose own device this is, or why the widget can't show them.
enum Owner {
    case person(KinwallClient, String)
    case demo
    case shared, signedOut, offline
    /// The family turned check-ins off (Settings → Features), which takes the battery with them.
    case checkInsOff

    static func current() async -> Owner {
        guard let client = try? widgetClient() else { return Demo.isOn ? .demo : .signedOut }
        async let features = client.features()
        guard let me = try? await client.me() else { return .offline }
        if await !features.checkIns { return .checkInsOff }
        return me.person.map { .person(client, $0) } ?? .shared
    }
}

struct OwnerProblemView: View {
    let owner: Owner
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch owner {
            case .shared:
                Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                Text("Only on a person's own device").font(.caption.weight(.semibold))
                Text("Set who uses this iPhone in Kinwall under Settings → Access.").font(.caption2).foregroundStyle(.secondary)
            case .offline: ProblemView(problem: .offline)
            case .checkInsOff: ProblemView(problem: .checkInsOff)
            default: ProblemView(problem: .signedOut)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The Kinwall Focus filter's "Hide health widgets" (native/ios/FocusFilter.swift): Take now,
/// Check-in and Energy say so instead of showing anything.
struct FocusHidden: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            ViewThatFits {
                Label("Hidden during this Focus", systemImage: "moon.fill").font(.caption.weight(.semibold))
                Image(systemName: "moon.fill")
            }
            .foregroundStyle(.secondary)
        } else {
            content
        }
    }
}

// MARK: - Daily check-in

struct CheckInEntry: TimelineEntry {
    let date: Date
    let owner: Owner
    let check: TempCheck?
    /// The Kinwall Focus filter's "Hide health widgets" (FocusHidden).
    var hidden = FocusSettings.current()?.hideHealth == true
    var demo: Bool { if case .demo = owner { true } else { false } }
    var person: String? { if case .person(_, let id) = owner { id } else if demo { DemoFamily.checkInPerson } else { nil } }
}

struct CheckInProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckInEntry { CheckInEntry(date: .now, owner: .demo, check: DemoFamily.tempCheck()) }
    func getSnapshot(in context: Context, completion: @escaping (CheckInEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(await load()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckInEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            // Look again on the hour and half hour, when the evening questions can open.
            let now = Date.now
            let m = Calendar.current.component(.minute, from: now), sec = Calendar.current.component(.second, from: now)
            let half = now.addingTimeInterval(Double(((m < 30 ? 30 : 60) - m) * 60 - sec))
            completion(Timeline(entries: [await load()], policy: .after(max(half, now.addingTimeInterval(5 * 60)))))
        }
    }
    private func load() async -> CheckInEntry {
        let owner = await Owner.current()
        switch owner {
        case .demo: return CheckInEntry(date: .now, owner: owner, check: DemoFamily.tempCheck())
        case .person(let client, let id): return CheckInEntry(date: .now, owner: owner, check: try? await client.tempCheck(id))
        default: return CheckInEntry(date: .now, owner: owner, check: nil)
        }
    }
}

struct CheckInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CheckIn", provider: CheckInProvider()) { entry in
            CheckInView(entry: entry).modifier(DemoBadge(on: entry.demo)).modifier(FocusHidden(on: entry.hidden)).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily check-in")
        .description("How you slept and how you feel in the morning; how the day went in the evening. Only on your own iPhone.")
        .supportedFamilies([.systemMedium])
    }
}

struct CheckInView: View {
    let entry: CheckInEntry

    var body: some View {
        if let check = entry.check, let person = entry.person {
            VStack(alignment: .leading, spacing: 8) {
                switch check.step {
                case .sleep:
                    question("How did you sleep?")
                    row(TempCheck.sleepAnswers.map { ($0.emoji, $0.label, TempCheckAnswerIntent(member: person, field: "sleep", value: $0.key)) })
                case .feelings:
                    question("How are you feeling?")
                    row(TempCheck.feelingChoices(custom: check.custom ?? [], limit: 5).map { ("", $0.capitalized, TempCheckAnswerIntent(member: person, field: "feelings", value: $0)) })
                case .goal:
                    question("Goal for today?")
                    Link(destination: URL(string: "family.kinwall.app:/open?to=checkin&member=\(person)")!) {
                        Label("Type it in Kinwall", systemImage: "square.and.pencil").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8).background(Capsule().fill(Palette.accent.opacity(0.15)))
                    }
                case .followup:
                    question("Did you finish your goal?")
                    if let goal = check.goal { Text(goal).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive() }
                    row(TempCheck.followupAnswers.map { ("", $0.label, TempCheckAnswerIntent(member: person, field: "followup", value: $0.key)) })
                case .drained:
                    question("How drained do you feel?")
                    row(TempCheck.drainedAnswers.map { ($0.emoji, $0.label, TempCheckAnswerIntent(member: person, field: "drained", value: $0.key)) })
                case .done:
                    Label("Checked in", systemImage: "checkmark.circle").font(.headline).foregroundStyle(.secondary)
                case .off:
                    Text("Check-in is off for you. A parent turns it on under Temp check in Kinwall.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if entry.check == nil, entry.person != nil {
            ProblemView(problem: .offline)
        } else {
            OwnerProblemView(owner: entry.owner)
        }
    }

    private func question(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Palette.accent)
    }

    /// Answer buttons; in the demo they open the check-in in the app instead (nothing is saved there either).
    private func row(_ answers: [(emoji: String, label: String, intent: TempCheckAnswerIntent)]) -> some View {
        HStack(spacing: 6) {
            ForEach(answers, id: \.label) { a in
                let label = VStack(spacing: 2) {
                    if !a.emoji.isEmpty { Text(a.emoji).font(.title2) }
                    Text(a.label).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 44).background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
                if entry.demo {
                    Link(destination: URL(string: "family.kinwall.app:/open?to=checkin&member=\(DemoFamily.checkInPerson)")!) { label }
                } else {
                    Button(intent: a.intent) { label }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// One check-in answer, straight to the server with the widgets' key (their own device only).
struct TempCheckAnswerIntent: AppIntent {
    static let title: LocalizedStringResource = "Answer the check-in"
    /// Writes to the family's Kinwall: only on an unlocked device (docs/WIDGETS-AND-WATCH.md, Locked iPhone).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = false
    @Parameter(title: "Person") var member: String
    @Parameter(title: "Question") var field: String
    @Parameter(title: "Answer") var value: String
    init() {}
    init(member: String, field: String, value: String) { self.member = member; self.field = field; self.value = value }
    func perform() async throws -> some IntentResult {
        var answer = TempCheckAnswer()
        switch field {
        case "sleep": answer.sleep = value
        case "feelings": answer.feelings = [value]
        case "followup": answer.followup = .init(outcome: value)
        default: answer.drained = value
        }
        try await widgetClient().answer(member, answer)
        WidgetCenter.shared.reloadTimelines(ofKind: "Battery") // the battery reads sleep, feelings and drained
        return .result()
    }
}

// MARK: - Energy battery

struct BatteryEntry: TimelineEntry {
    let date: Date
    let owner: Owner
    let battery: Battery?
    var hidden = FocusSettings.current()?.hideHealth == true
    var demo: Bool { if case .demo = owner { true } else { false } }
    var checkInsOff: Bool { if case .checkInsOff = owner { true } else { false } }
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry { BatteryEntry(date: .now, owner: .demo, battery: DemoFamily.battery()) }
    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(await load()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        // A few times a day; a check-in answer reloads it too (TempCheckAnswerIntent).
        Task { completion(Timeline(entries: [await load()], policy: .after(.now.addingTimeInterval(3 * 3600)))) }
    }
    private func load() async -> BatteryEntry {
        let owner = await Owner.current()
        switch owner {
        case .demo: return BatteryEntry(date: .now, owner: owner, battery: DemoFamily.battery())
        case .person(let client, let id): return BatteryEntry(date: .now, owner: owner, battery: try? await client.battery(id))
        default: return BatteryEntry(date: .now, owner: owner, battery: nil)
        }
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Battery", provider: BatteryProvider()) { entry in
            BatteryView(entry: entry).modifier(DemoBadge(on: entry.demo)).modifier(FocusHidden(on: entry.hidden)).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Energy battery")
        .description("A rough guess at your energy today. On the Lock Screen, only the gauge. Only on your own iPhone.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct BatteryView: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let summary = entry.battery?.summary
        if family == .accessoryCircular {
            // The Lock Screen shows the gauge only: no reasons, no name, nothing to read over a shoulder.
            Gauge(value: Double(summary?.level ?? 0), in: 0...100) { Image(systemName: "bolt.fill") } currentValueLabel: { Text(summary.map { "\($0.level)" } ?? (entry.checkInsOff ? "Off" : "–")) }
                .gaugeStyle(.accessoryCircularCapacity).privacySensitive()
        } else if let summary {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("🔋 ENERGY").font(.caption.weight(.heavy)).foregroundStyle(Palette.accent)
                    Spacer()
                }
                Gauge(value: Double(summary.level), in: 0...100) { EmptyView() }.gaugeStyle(.linearCapacity).tint(summary.level >= 50 ? .green : summary.level >= 25 ? .orange : .red)
                Text(summary.line).font(family == .systemSmall ? .subheadline.weight(.semibold) : .headline).lineLimit(2).privacySensitive()
                if family == .systemMedium {
                    ForEach(summary.reasons, id: \.self) { Text("· \($0)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    if let headsUp = summary.headsUp { Text(headsUp).font(.caption.weight(.semibold)).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .privacySensitive()
            .padding(.bottom, entry.demo ? 10 : 0) // clear of the Demo badge
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if entry.battery != nil {
            Text("Turn on the Energy battery in Temp check settings.").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if case .person = entry.owner {
            ProblemView(problem: .offline)
        } else {
            OwnerProblemView(owner: entry.owner)
        }
    }
}

struct KinwallHealthWidgets: WidgetBundle {
    var body: some Widget {
        CheckInWidget()
        BatteryWidget()
    }
}
