import ActivityKit
import AppIntents
import KinwallKit
import SwiftUI
import WidgetKit

// The Live Activities (modules/kinwall-native/ios/LiveActivities.swift starts them; the web app
// decides what they say): a cooking timer, a shopping trip, the next leave-by or start-prep
// time, and a medicine that's due, on the Lock Screen and in the Dynamic Island. Countdowns tick on their own
// (Text(timerInterval:)); when a timer or leave-by time passes, the activity goes stale and says
// "Done" or "Leave now" without an update.

struct KinwallLiveActivity: Widget {
    /// iOS 18 and later add a small layout (SmallActivity) for the Apple Watch Smart Stack (iOS 18)
    /// and the CarPlay Dashboard (iOS 26), which otherwise get a generic one.
    var body: some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return Self.configuration { FamilyActivity(context: $0) }.supplementalActivityFamilies([.small])
        } else {
            return Self.configuration { LockScreenActivity(context: $0) }
        }
    }

    /// The Lock Screen view is the parameter: from iOS 18 it's one that also draws the small family.
    static func configuration(_ lockScreen: @escaping (ActivityViewContext<KinwallActivityAttributes>) -> some View) -> some WidgetConfiguration {
        ActivityConfiguration(for: KinwallActivityAttributes.self) { context in
            lockScreen(context)
                // The system's own background (light or dark with the phone) and text: the accent only
                // marks the countdown and the main button, as in the Dynamic Island.
                .activityBackgroundTint(nil)
                .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            DynamicIsland {
                // The leading region is narrow beside the camera: only the icon there, and what it's
                // about gets the island's full width below.
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.icon).font(.title3).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Trailing(context: context).font(.title3.weight(.semibold)).lineLimit(1).frame(maxWidth: 96, alignment: .trailing)
                        .foregroundStyle(ActivityTheme.accentOnDark).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.headline).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                        // The recipe, store or event under it (a medicine's headline already says whose).
                        if context.attributes.kind != "medication" {
                            Text(context.attributes.name).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                        }
                        if context.attributes.kind == "shopping" { ShoppingLineView(context: context).font(.subheadline).foregroundStyle(.secondary) }
                        else if let line = context.stepLine { Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        if context.attributes.kind == "shopping" { ShoppingButtons(context: context) }
                        if context.attributes.kind == "medication" { Text(context.medicationLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1); DoseButtons(context: context) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(context.attributes.icon)
            } compactTrailing: {
                Trailing(context: context).frame(maxWidth: 52).foregroundStyle(ActivityTheme.accentOnDark)
            } minimal: {
                Text(context.attributes.icon)
            }
            .widgetURL(context.attributes.link)
            .keylineTint(ActivityTheme.accentOnDark)
        }
    }
}

@available(iOS 18.0, *)
struct FamilyActivity: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    @Environment(\.activityFamily) private var family
    var body: some View {
        if family == .small { SmallActivity(context: context) } else { LockScreenActivity(context: context) }
    }
}

/// Watch and CarPlay: the icon and the countdown (or count), and the headline. No buttons: the
/// Watch opens the full one on a tap, and CarPlay isn't for tapping. A medicine stays the web app's
/// headline ("Time for Maya's medicine"), never its name.
struct SmallActivity: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(context.attributes.icon)
                Spacer(minLength: 4)
                Trailing(context: context).font(.headline).foregroundStyle(ActivityTheme.accent).lineLimit(1)
            }
            Text(context.headline).font(.subheadline.weight(.semibold)).foregroundStyle(context.due ? ActivityTheme.accent : .primary).lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Words

extension KinwallActivityAttributes {
    var icon: String { ["cooking": "⏲️", "shopping": "🛒", "leave": "🚗", "prep": "🍳", "medication": "💊"][kind] ?? "📅" }
    /// Open: shopping mode for a trip, the calendar for a leave-by; the app as it was for cooking.
    var link: URL? {
        switch kind {
        case "shopping": listId.flatMap { URL(string: "family.kinwall.app:/open?to=lists/\($0)/shop") }
        case "leave", "prep", "medication": URL(string: "family.kinwall.app:/open?to=calendar")
        default: nil
        }
    }
}

extension ActivityViewContext<KinwallActivityAttributes> {
    var s: KinwallActivityAttributes.ContentState { state }
    /// Past its time: a timer that's up, a leave-by or start-prep time that has come. A cooking range
    /// goes stale at its check, and isn't up until its end.
    var due: Bool { attributes.kind == "cooking" ? cooking.countdownTo == nil || (isStale && s.check == nil) : isStale || s.done || (s.date.map { $0 <= .now } ?? false) }
    /// A cooking timer's headline and countdown now: a range's check, then its end (KinwallKit CookingLine).
    var cooking: CookingLine { CookingLine(title: s.title, end: s.date, done: s.done, check: s.check, before: s.beforeCheck, after: s.afterCheck, now: .now) }

    var headline: String {
        switch attributes.kind {
        case "cooking": due ? "Done: \(s.title)" : cooking.headline
        case "shopping": s.count == 0 ? "All done at \(attributes.name)" : s.title.isEmpty ? "\(s.count) left" : s.title
        case "medication": s.title // the web app's headline ("Time for Maya's medicine")
        default: due ? (s.detail ?? "Time to go") : s.title
        }
    }

    /// A cooking timer's step and how many others are running, under the recipe.
    var stepLine: String? {
        guard attributes.kind == "cooking" else { return nil }
        // A range's headline is its check words, so its name goes in front here.
        let line = [s.check == nil ? nil : s.title, s.detail, s.count > 0 ? "+\(s.count) more" : nil].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// Shopping: where the current item is, then what's after it (KinwallKit ShoppingLine). `detail`
    /// is the current item's aisle; the queue carries it first, then up to four after it.
    var shoppingLine: ShoppingLine {
        let after = (s.queue ?? []).drop { $0.id != s.itemId }.dropFirst().first
        return ShoppingLine(aisle: s.detail, next: after.map { ($0.title, $0.aisle) }, left: s.count)
    }

    /// Kind words only, never "missed": "Due now · still time until 8:00 PM", "Still time · until 8:00 PM".
    var medicationLine: String {
        let until = (attributes.endsAt ?? s.date).map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return s.detail == "late" ? "Still time · until \(until)" : "Due now · still time until \(until)"
    }
}

/// The countdown, or what the activity counts.
struct Trailing: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        if context.attributes.kind == "shopping" {
            Text("\(context.s.count) left").monospacedDigit()
        } else if let date = context.attributes.kind == "cooking" ? context.cooking.countdownTo : context.s.date, !context.due {
            Text(timerInterval: Date.now...max(date, .now), countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            Text(context.attributes.kind == "cooking" ? "Done" : "Now")
        }
    }
}

// MARK: - Lock Screen

struct LockScreenActivity: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(context.attributes.icon).font(.title3)
                Text(lead).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Trailing(context: context).font(.title2.weight(.semibold)).foregroundStyle(ActivityTheme.accent).lineLimit(1).frame(maxWidth: 110, alignment: .trailing)
            }
            Text(context.headline).font(.headline).foregroundStyle(context.due ? ActivityTheme.accent : .primary).lineLimit(2)
            if let line = context.stepLine { Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            if context.attributes.kind == "shopping" {
                ShoppingLineView(context: context).font(.subheadline).foregroundStyle(.secondary)
                ShoppingButtons(context: context)
            }
            if context.attributes.kind == "medication" {
                Text(context.medicationLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                DoseButtons(context: context)
            }
        }
        .padding(16)
    }

    /// Leave / prep: "Soccer practice · leave in" before the countdown; the others: their name (a
    /// cooking timer's step goes under its headline).
    private var lead: String {
        switch context.attributes.kind {
        case "leave": context.due ? context.attributes.name : "\(context.attributes.name) · leave in"
        case "prep": context.due ? context.attributes.name : "\(context.attributes.name) · start prep in"
        // Shopping: the count is on the right; where things are goes under the item (ShoppingLineView).
        default: context.attributes.name // a medicine: the web app's label, generic unless the device opted into names
        }
    }
}

/// "Dairy · then Dishwasher tablets (Aisle 17)": only the next item's name gives way when it's long,
/// never where things are. Nothing once the trip is done.
struct ShoppingLineView: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        let line = context.shoppingLine
        if context.s.count > 0, !line.text.isEmpty {
            HStack(spacing: 0) {
                Text(line.lead).layoutPriority(2)
                if !line.name.isEmpty { Text(line.name).truncationMode(.tail) }
                if !line.tail.isEmpty { Text(line.tail).layoutPriority(2) }
            }
            .lineLimit(1)
        }
    }
}

/// Taken and Snooze 10 min (MarkDoseActivityIntent, native/ios/LiveActivityIntents.swift).
struct DoseButtons: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        if let dose = context.attributes.dose {
            HStack(spacing: 10) {
                Button(intent: MarkDoseActivityIntent(medicationId: dose.medicationId, date: dose.date, time: dose.time, action: "taken")) {
                    Label("Taken", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(ActivityTheme.accent)
                Button(intent: MarkDoseActivityIntent(medicationId: dose.medicationId, date: dose.date, time: dose.time, action: "snooze")) {
                    Label("Snooze 10 min", systemImage: "zzz").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.primary)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

/// Got it ticks the next item (GotItIntent, native/ios/LiveActivityIntents.swift); Open opens shopping mode.
struct ShoppingButtons: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        HStack(spacing: 10) {
            // On a combined trip the item can be on the other list: its entry carries that list's id.
            if let itemId = context.s.itemId, let listId = context.s.queue?.first(where: { $0.id == itemId })?.listId ?? context.attributes.listId {
                Button(intent: GotItIntent(listId: listId, itemId: itemId)) {
                    Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(ActivityTheme.accent)
            }
            if let link = context.attributes.link {
                Link(destination: link) { Label("Open", systemImage: "cart").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(.primary)
            }
        }
        .font(.subheadline.weight(.semibold))
    }
}

// MARK: - Colors

/// Kinwall's blue (Peacock), only as an accent on the system's background: the deep peacock
/// (10.9:1 on the light Lock Screen card), the sky blue (7.6:1 on the dark card, 9.4:1 on the black
/// Dynamic Island).
/// The family's colors (attributes.colors) still tint the cooking alarm, not the activity.
enum ActivityTheme {
    static let accent = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(accentOnDark) : UIColor(red: 0x12 / 255, green: 0x38 / 255, blue: 0x57 / 255, alpha: 1) })
    static let accentOnDark = Color(hex: "#6CB4EE")!
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.count == 7, hex.first == "#", let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
