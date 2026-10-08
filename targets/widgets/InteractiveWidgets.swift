import SwiftUI
import WidgetKit
import AppIntents
import KinwallKit

// Interactive widgets (docs/WIDGETS-AND-WATCH.md): tick chores and list items off from the Home
// Screen. Their settings and actions live in WidgetIntents.swift.

// MARK: - Chores widget

struct ChoresEntry: TimelineEntry {
    let date: Date
    let day: String
    let chores: [ChoreDay]
    let member: MemberEntity?
    let signedOut: Bool
    var demo = false
    /// The family turned chores off.
    var off = false
    /// Smart Stack: a little while any are left (chores have no time of day to rise toward).
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: off ? 0 : Float(chores.filter { !$0.isTicked }.count)) }
}

struct ChoresProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChoresEntry { ChoresEntry(date: .now, day: "", chores: [], member: nil, signedOut: false) }
    func snapshot(for configuration: ChoresConfig, in context: Context) async -> ChoresEntry { await entry(configuration) }
    func timeline(for configuration: ChoresConfig, in context: Context) async -> Timeline<ChoresEntry> {
        Timeline(entries: [await entry(configuration)], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
    private func entry(_ config: ChoresConfig) async -> ChoresEntry {
        let client = try? widgetClient()
        let demo = client == nil && Demo.isOn // the demo family's sample chores (KinwallWidgets.swift)
        guard client != nil || demo else { return ChoresEntry(date: .now, day: "", chores: [], member: nil, signedOut: true) }
        let settings = try? await client?.settings()
        if settings?.on.chores == false { return ChoresEntry(date: .now, day: "", chores: [], member: nil, signedOut: false, off: true) }
        let tz = settings?.timezone
        let day = HouseholdDate.key(timezone: tz)
        let all = demo ? Demo.chores : ((try? await client?.chores(on: day)) ?? [])
        let mine: [ChoreDay]
        let member: MemberEntity?
        var person: Member?
        if !config.onlyAnyone, let id = config.member, id != MemberOptions.everyone { person = (demo ? Demo.members : try? await client?.members())?.first { $0.id == id } }
        if config.onlyAnyone {
            member = .anyone; mine = all.filter(\.isAnyone)
        } else if let m = person {
            member = MemberEntity(id: m.id, name: m.name, avatar: m.avatar)
            mine = all.filter { $0.memberId == m.id || (config.includeAnyone && $0.isAnyone) }
        } else {
            member = nil; mine = config.includeAnyone ? all : all.filter { !$0.isAnyone } // everyone
        }
        return ChoresEntry(date: .now, day: day, chores: mine.sorted { !$0.isTicked && $1.isTicked }, member: member, signedOut: false, demo: demo)
    }
}

struct ChoresWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Chores", intent: ChoresConfig.self, provider: ChoresProvider()) { entry in
            ChoresView(entry: entry).modifier(DemoBadge(on: entry.demo)).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Chores")
        .description("Tick off today's chores. Set to a person, Anyone chores count for them; otherwise Kinwall asks who did it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ChoresView: View {
    let entry: ChoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.signedOut { ProblemView(problem: .signedOut) } else if entry.off { ProblemView(problem: .choresOff) } else {
            let limit = family == .systemLarge ? 8 : 3
            let left = entry.chores.filter { !$0.isTicked }.count
            VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 6) {
                HStack {
                    Text(entry.member.map { "\($0.avatar ?? "") \($0.name)".uppercased() } ?? "CHORES").font(.caption.weight(.heavy)).foregroundStyle(Palette.accent).lineLimit(1)
                    Spacer()
                    if !entry.chores.isEmpty {
                        Text(left == 0 ? "All done 🎉" : "\(left) left").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                if entry.chores.isEmpty { Text("No chores today.").font(family == .systemSmall ? .footnote : .subheadline).foregroundStyle(.secondary) }
                ForEach(entry.chores.prefix(limit)) { chore in row(chore) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func row(_ chore: ChoreDay) -> some View {
        let label = HStack(spacing: family == .systemSmall ? 6 : 8) {
            if family == .systemSmall {
                // Small: the chore's emoji is the checkbox, so the title gets the width (and two lines).
                ZStack {
                    Circle().strokeBorder(chore.isTicked ? Color.green : Color.secondary.opacity(0.5), lineWidth: 1.5)
                        .background(Circle().fill(chore.isTicked ? Color.green : Color.clear))
                    if chore.isTicked { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                    else { Text(chore.emoji ?? "⭐").font(.footnote) }
                }
                .frame(width: 26, height: 26)
                Text(chore.title).font(.footnote.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
                    .strikethrough(chore.isTicked).foregroundStyle(chore.isTicked ? .secondary : .primary)
            } else {
                Image(systemName: chore.isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(chore.isTicked ? .green : .secondary)
                Text("\(chore.emoji ?? "⭐") \(chore.title)").font(.subheadline.weight(.semibold)).lineLimit(1)
                    .strikethrough(chore.isTicked).foregroundStyle(chore.isTicked ? .secondary : .primary)
            }
            Spacer(minLength: 0)
        }
        // A person's widget credits them for Anyone chores. Without a person, an Anyone chore opens the
        // app to ask "Who did it?", and an unfinished checklist has to be finished there first.
        let person = entry.member?.isAnyone == false ? entry.member?.id : nil
        let needsApp = !chore.isTicked && ((chore.checklist.map { !$0.isFinished } ?? false) || (chore.isAnyone && person == nil))
        if entry.demo {
            Link(destination: URL(string: "family.kinwall.app:/open?to=chores")!) { label } // sample data: ticking happens in the demo itself
        } else if needsApp {
            Link(destination: URL(string: "family.kinwall.app:/open?to=chores&done=\(chore.id)")!) { label }
        } else {
            Button(intent: ToggleChoreIntent(choreId: chore.id, date: entry.day, done: !chore.isTicked, creditTo: chore.memberId ?? person)) { label }
                .buttonStyle(.plain)
        }
    }
}

// MARK: - List widget

struct ListEntry: TimelineEntry {
    let date: Date
    let list: ListDetail?
    let signedOut: Bool
    var demo = false
    /// The family turned lists off.
    var off = false
}

struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListEntry { ListEntry(date: .now, list: nil, signedOut: false) }
    func snapshot(for configuration: ListConfig, in context: Context) async -> ListEntry { await entry(configuration) }
    func timeline(for configuration: ListConfig, in context: Context) async -> Timeline<ListEntry> {
        Timeline(entries: [await entry(configuration)], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
    private func entry(_ config: ListConfig) async -> ListEntry {
        guard let client = try? widgetClient() else {
            return Demo.isOn ? ListEntry(date: .now, list: Demo.groceries, signedOut: false, demo: true) : ListEntry(date: .now, list: nil, signedOut: true)
        }
        if await !client.features().lists { return ListEntry(date: .now, list: nil, signedOut: false, off: true) }
        var id = config.list
        if id == nil { id = (try? await FamilyList.groceries(in: client.lists()))?.id } // default: Groceries
        guard let id, let detail = try? await client.list(id) else { return ListEntry(date: .now, list: nil, signedOut: false) }
        return ListEntry(date: .now, list: detail, signedOut: false)
    }
}

struct ListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "List", intent: ListConfig.self, provider: ListProvider()) { entry in
            ListWidgetView(entry: entry).modifier(DemoBadge(on: entry.demo)).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("List")
        .description("Tick items off a list, like Groceries.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ListWidgetView: View {
    let entry: ListEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.signedOut { ProblemView(problem: .signedOut) } else if entry.off { ProblemView(problem: .listsOff) } else if let list = entry.list {
            let open = list.items.filter { !$0.done }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(list.list.emoji ?? "") \(list.list.name)".uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Palette.accent).lineLimit(1)
                    Spacer()
                    Text(open.isEmpty ? "All done 🎉" : "\(open.count) left").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(open.prefix(family == .systemLarge ? 9 : 3)) { item in
                    let label = HStack(spacing: 8) {
                        Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let q = item.quantity, !q.isEmpty { Text(q).font(.caption).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                    }
                    if entry.demo {
                        Link(destination: URL(string: "family.kinwall.app:/open?to=lists")!) { label } // sample data: ticking happens in the demo itself
                    } else {
                        Button(intent: ToggleItemIntent(listId: list.list.id, itemId: item.id, done: true)) { label }
                            .buttonStyle(.plain)
                    }
                }
                if open.count > (family == .systemLarge ? 9 : 3) { Text("+\(open.count - (family == .systemLarge ? 9 : 3)) more").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Choose a list: press and hold, then Edit Widget.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
