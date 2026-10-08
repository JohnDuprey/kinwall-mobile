import Foundation

/// One name in the family's groceries catalog (GET /api/lists/remembered), for Siri's one-sentence
/// "Add milk to Kinwall" (native/ios/SiriIntents.swift ItemEntity).
public struct RememberedItem: Codable, Hashable, Sendable {
    public let title: String
    /// Times added to a shopping list (0: added to the catalog only).
    public let uses: Int
    public let lastUsed: String?
    public init(title: String, uses: Int, lastUsed: String?) { self.title = title; self.uses = uses; self.lastUsed = lastUsed }

    /// The title without emoji, what Siri hears: "Milk 🥛" is "Milk".
    public var plainName: String {
        String(String.UnicodeScalarView(title.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || $0.properties.isEmojiModifier || ($0.properties.isEmoji && $0.value > 0x238C) || $0.value == 0xFE0F || $0.value == 0x200D)
        })).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// How many groceries Siri can hear in one sentence: SiriBudget.itemCap.
    public static let siriCap = SiriBudget.itemCap

    /// The most used first (then the most recent), at most `cap`, each plain name once.
    public static func forSiri(_ items: [RememberedItem], cap: Int = siriCap) -> [RememberedItem] {
        var seen = Set<String>()
        return items
            .sorted { ($0.uses, $0.lastUsed ?? "") > ($1.uses, $1.lastUsed ?? "") }
            .filter { !$0.plainName.isEmpty && seen.insert($0.plainName.lowercased()).inserted }
            .prefix(cap).map { $0 }
    }

    /// The items whose plain name holds `text`, case and emoji ignored.
    public static func matching(_ text: String, in items: [RememberedItem]) -> [RememberedItem] {
        let wanted = RememberedItem(title: text, uses: 0, lastUsed: nil).plainName
        return items.filter { $0.plainName.localizedCaseInsensitiveContains(wanted) }
    }
}

/// Apple allows 1,000 App Shortcut phrases per app (per language), and each value of a phrase's
/// parameter counts once per phrase that holds it (WWDC23 "Spotlight your app with App Shortcuts").
/// We aim under 900 so a miscount doesn't cost Siri its phrases. These counts must match
/// KinwallShortcuts in native/ios/SiriIntents.swift; the entity queries cap their suggestions here.
///
///     16 plain phrases
///   +  2 list phrases  × 20 lists   =  40
///   +  1 store phrase  × 20 stores  =  20
///   +  1 chore phrase  × 40 chores  =  40
///   +  7 item phrases  × 112 items  = 784
///   = 900
public enum SiriBudget {
    public static let limit = 900
    public static let plainPhrases = 20
    public static let listPhrases = 2, maxLists = 20
    public static let storePhrases = 1, maxStores = 20
    public static let chorePhrases = 1, maxChores = 40
    public static let itemPhrases = 7
    /// What's left after everything else, split across the item phrases.
    public static var itemCap: Int {
        (limit - plainPhrases - listPhrases * maxLists - storePhrases * maxStores - chorePhrases * maxChores) / itemPhrases
    }
    public static var total: Int {
        plainPhrases + listPhrases * maxLists + storePhrases * maxStores + chorePhrases * maxChores + itemPhrases * itemCap
    }
}
