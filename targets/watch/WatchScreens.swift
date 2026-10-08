import SwiftUI
import KinwallKit
import WidgetKit

// MARK: - Today

/// Now & Next with the live countdown, then the rest of today.
struct TodayView: View {
    let client: KinwallClient
    @State private var board: Board?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if let board {
                    let (now, next) = board.nowAndNext(at: .now)
                    if let now { row("NOW", now) }
                    if let next { row("NEXT", next) }
                    if now == nil && next == nil { Text("Nothing more today").foregroundStyle(.secondary) }
                    let later = board.events.filter { $0.date == board.today && $0.id != now?.id && $0.id != next?.id && ($0.allDay || ($0.endDate ?? .distantFuture) > .now) }
                    if !later.isEmpty {
                        Section("Later today") {
                            ForEach(later) { e in
                                VStack(alignment: .leading) {
                                    Text(e.title).font(.headline).lineLimit(2)
                                    Text(e.allDay ? "All day" : (e.startDate ?? .now).formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if failed {
                    Text("Can't reach Kinwall right now").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Today")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ label: String, _ e: BoardEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).foregroundStyle(.orange)
            Text(e.title).font(.headline).lineLimit(2)
            if label == "NOW", let end = e.endDate {
                Text("ends in \(end, style: .timer)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            } else if let leave = e.leaveDate, leave > .now {
                Text("🚗 leave in \(leave, style: .timer)").font(.caption.weight(.semibold)).monospacedDigit()
            } else {
                Text(e.allDay ? "All day" : (e.startDate ?? .now).formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        do { board = try await client.board(days: 1); failed = false } catch { failed = board == nil }
    }
}

// MARK: - My chores

/// This Watch's person's chores for today (plus Anyone chores, credited to them). Tap to tick off.
struct ChoresView: View {
    let client: KinwallClient
    @AppStorage("person") private var personId = "" // chosen on the Watch; "" = not chosen yet
    @State private var members: [Member] = []
    @State private var chores: [ChoreDay] = []
    @State private var day = ""
    @State private var failed = false
    @State private var off = false // the family turned chores off

    var body: some View {
        NavigationStack {
            List {
                if off {
                    Text("Chores are turned off in Kinwall.").foregroundStyle(.secondary)
                } else if members.isEmpty && !failed {
                    ProgressView()
                } else if failed {
                    Text("Can't reach Kinwall right now").foregroundStyle(.secondary)
                } else if personId.isEmpty || !members.contains(where: { $0.id == personId }) {
                    Section("Whose Watch is this?") {
                        ForEach(members) { m in
                            Button("\(m.avatar ?? "🙂") \(m.name)") { personId = m.id; Task { await load() } }
                        }
                    }
                } else {
                    let mine = chores.filter { $0.memberId == personId || $0.isAnyone }.sorted { !$0.isTicked && $1.isTicked }
                    if mine.isEmpty { Text("No chores today 🎉").foregroundStyle(.secondary) }
                    ForEach(mine) { chore in choreRow(chore) }
                    Section {
                        Button("Not you? Change person") { personId = "" }.font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(members.first { $0.id == personId }.map { "\($0.avatar ?? "") \($0.name)" } ?? "Chores")
        }
        .task { await load() }
    }

    @ViewBuilder private func choreRow(_ chore: ChoreDay) -> some View {
        let needsPhone = !chore.isTicked && (chore.checklist.map { !$0.isFinished } ?? false)
        Button {
            guard !needsPhone else { return }
            Task { await toggle(chore) }
        } label: {
            HStack {
                Image(systemName: chore.isTicked ? "checkmark.circle.fill" : "circle").foregroundStyle(chore.isTicked ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text("\(chore.emoji ?? "⭐") \(chore.title)").lineLimit(2).strikethrough(chore.isTicked)
                    if needsPhone, let cl = chore.checklist {
                        Text("☑ \(cl.done)/\(cl.total) · finish on iPhone").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func toggle(_ chore: ChoreDay) async {
        WKHaptic.play(chore.isTicked ? .click : .success)
        do {
            if chore.isTicked { try await client.uncomplete(chore: chore.id, on: day) }
            else { try await client.complete(chore: chore.id, on: day, by: chore.memberId ?? personId) } // Anyone chores count for this Watch's person
        } catch { WKHaptic.play(.failure) }
        await load()
    }

    private func load() async {
        do {
            let settings = try? await client.settings()
            off = settings?.on.chores == false
            if off { return }
            day = HouseholdDate.key(timezone: settings?.timezone)
            async let m = client.members()
            async let c = client.chores(on: day)
            (members, chores) = try await (m, c)
            failed = false
        } catch { failed = members.isEmpty }
    }
}

// MARK: - Check-in

/// One tap for "How did you sleep?" on the owner's Watch (health data: only with a key that
/// belongs to them; a shared Watch says so). The rest of the check-in is on the iPhone.
struct CheckInView: View {
    let client: KinwallClient
    @State private var person: String?
    @State private var check: TempCheck?
    @State private var shared = false
    @State private var off = false // the family turned check-ins off

    var body: some View {
        NavigationStack {
            List {
                if off {
                    Text("Check-ins are turned off in Kinwall.").foregroundStyle(.secondary)
                } else if shared {
                    Text("Check-in is only on a person's own Watch.").foregroundStyle(.secondary)
                } else if let check, let person {
                    switch check.step {
                    case .sleep:
                        Section("How did you sleep?") {
                            ForEach(TempCheck.sleepAnswers, id: \.key) { a in
                                Button { Task { await answer(person, a.key) } } label: { Text("\(a.emoji) \(a.label)") }
                            }
                        }
                    case .done: Label("Checked in", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    case .off: Text("Check-in is off for you.").foregroundStyle(.secondary)
                    default: Text("Finish your check-in on your iPhone.").foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Check-in")
        }
        .task { await load() }
    }

    private func answer(_ person: String, _ sleep: String) async {
        do { try await client.answer(person, TempCheckAnswer(sleep: sleep)); WKHaptic.play(.success) } catch { WKHaptic.play(.failure) }
        await load()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func load() async {
        off = await !client.features().checkIns
        if off { return }
        guard let me = try? await client.me() else { return }
        guard let id = me.person else { shared = true; return }
        person = id
        check = try? await client.tempCheck(id)
    }
}

// MARK: - Take now

/// Medicines due now, with Taken and Snooze (10 minutes). What the server shares with the Watch's
/// key: a person's own Watch sees their names; a shared one "Medicine". Hidden while none are due.
struct MedsView: View {
    let client: KinwallClient
    @State private var due: DueDoses?
    @State private var members: [Member] = []
    @State private var off = false // medicines off (reminders off, or the Health tracker off)

    var body: some View {
        NavigationStack {
            List {
                if off {
                    Text("Medicine is turned off in Kinwall.").foregroundStyle(.secondary)
                } else if let due {
                    if due.doses.isEmpty { Text("Nothing due right now").foregroundStyle(.secondary) }
                    ForEach(due.doses) { d in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(members.first { $0.id == d.memberId }.map { "\($0.avatar ?? "") \($0.name)" } ?? "Someone").font(.headline)
                            Text([d.name, d.dose].compactMap { $0 }.joined(separator: " ").isEmpty ? "Medicine" : [d.name, d.dose].compactMap { $0 }.joined(separator: " "))
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Taken") { Task { await mark(d, .taken) } }.tint(.green)
                                Button("Snooze") { Task { await mark(d, .snooze) } }
                            }
                            .buttonStyle(.bordered).font(.footnote)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("💊 Take now")
        }
        .task { await load() }
    }

    private func mark(_ d: DueDose, _ action: KinwallClient.DoseAction) async {
        do { try await client.mark(d, action); WKHaptic.play(.success) } catch { WKHaptic.play(.failure) }
        await load()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func load() async {
        off = await !client.medicinesOn()
        if off { return }
        async let d = client.dueDoses()
        async let m = client.members()
        due = (try? await d) ?? DueDoses(names: false, doses: []) // 404: the family has medicines off
        members = (try? await m) ?? members
    }
}

// MARK: - Lists

/// The family's lists; big rows to tick off while shopping, and dictation to add.
struct ListsView: View {
    let client: KinwallClient
    @State private var lists: [FamilyList] = []
    @State private var failed = false
    @State private var off = false // the family turned lists off

    var body: some View {
        NavigationStack {
            List {
                if off { Text("Lists are turned off in Kinwall.").foregroundStyle(.secondary) }
                else if lists.isEmpty && !failed { ProgressView() }
                if failed { Text("Can't reach Kinwall right now").foregroundStyle(.secondary) }
                ForEach(lists) { l in
                    NavigationLink {
                        ListItemsView(client: client, list: l)
                    } label: {
                        HStack {
                            Text("\(l.emoji ?? "📝") \(l.name)").lineLimit(1)
                            Spacer()
                            Text("\(l.openCount)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Lists")
        }
        .task { await load() }
    }

    private func load() async {
        off = await !client.features().lists
        if off { lists = []; return }
        do { lists = try await client.lists().filter { !$0.archived }; failed = false } catch { failed = lists.isEmpty }
    }
}

struct ListItemsView: View {
    let client: KinwallClient
    let list: FamilyList
    @State private var items: [ListItem] = []
    @State private var newItem = ""
    @State private var addError: String?

    var body: some View {
        List {
            TextField("Add an item", text: $newItem) // dictation or Scribble
                .onSubmit { Task { await add() } }
            if let addError { Text(addError).font(.footnote).foregroundStyle(.red) }
            ForEach(items.sorted { !$0.done && $1.done }) { item in
                Button {
                    Task { await toggle(item) }
                } label: {
                    HStack {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(item.done ? .green : .secondary)
                        Text(item.quantity.map { "\(item.title) · \($0)" } ?? item.title).strikethrough(item.done).lineLimit(2)
                    }
                    .padding(.vertical, 4) // big targets for a quick tap in the store
                }
            }
        }
        .navigationTitle(list.name)
        .task { await load() }
    }

    private func toggle(_ item: ListItem) async {
        WKHaptic.play(.click)
        try? await client.setDone(!item.done, item: item.id, in: list.id)
        await load()
    }

    private func add() async {
        let title = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newItem = ""
        do {
            _ = try await client.addItem(title, to: list.id) // only once the server hands it back
            addError = nil
        } catch {
            newItem = title // kept, to try again
            addError = (error as? LocalizedError)?.errorDescription ?? "Couldn't add \(title)."
            WKHaptic.play(.failure)
        }
        await load()
    }

    private func load() async { if let detail = try? await client.list(list.id) { items = detail.items } }
}

import WatchKit
private enum WKHaptic {
    static func play(_ type: WKHapticType) { WKInterfaceDevice.current().play(type) }
}
