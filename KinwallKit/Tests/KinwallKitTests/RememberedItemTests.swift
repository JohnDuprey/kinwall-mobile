import Testing
@testable import KinwallKit

@Suite struct RememberedItemTests {
    @Test func plainNameDropsEmoji() {
        #expect(RememberedItem(title: "Milk 🥛", uses: 1, lastUsed: nil).plainName == "Milk")
        #expect(RememberedItem(title: "🍎 Honeycrisp apples", uses: 1, lastUsed: nil).plainName == "Honeycrisp apples")
        #expect(RememberedItem(title: "Tea ☕️", uses: 1, lastUsed: nil).plainName == "Tea")
        #expect(RememberedItem(title: "2% milk", uses: 1, lastUsed: nil).plainName == "2% milk") // digits and # stay
    }
    @Test func matchingIgnoresCaseAndEmoji() {
        let items = [RememberedItem(title: "Milk 🥛", uses: 3, lastUsed: nil), RememberedItem(title: "Oat milk", uses: 1, lastUsed: nil), RememberedItem(title: "Eggs", uses: 9, lastUsed: nil)]
        #expect(RememberedItem.matching("milk", in: items).map(\.title) == ["Milk 🥛", "Oat milk"])
        #expect(RememberedItem.matching("MILK 🥛", in: items).count == 2)
        #expect(RememberedItem.matching("bread", in: items).isEmpty)
    }
    @Test func mostUsedFirstCappedAndOncePerName() {
        let items = [
            RememberedItem(title: "Eggs", uses: 2, lastUsed: "2026-09-01"),
            RememberedItem(title: "Milk", uses: 9, lastUsed: "2026-09-01"),
            RememberedItem(title: "Milk 🥛", uses: 1, lastUsed: "2026-09-02"), // same plain name: the more used one wins
            RememberedItem(title: "Bread", uses: 2, lastUsed: "2026-09-20"),
            RememberedItem(title: "🥛", uses: 50, lastUsed: nil), // nothing to say
        ]
        #expect(RememberedItem.forSiri(items).map(\.title) == ["Milk", "Bread", "Eggs"])
        #expect(RememberedItem.forSiri(items, cap: 2).map(\.title) == ["Milk", "Bread"])
        let many = (0..<1000).map { RememberedItem(title: "Item \($0)", uses: $0, lastUsed: nil) }
        #expect(RememberedItem.forSiri(many).count == RememberedItem.siriCap)
        #expect(RememberedItem.forSiri(many).first?.title == "Item 999")
    }
    @Test func siriPhrasesFitApplesLimit() {
        #expect(RememberedItem.siriCap == 111)
        #expect(SiriBudget.total <= SiriBudget.limit)
        #expect(SiriBudget.limit < 1000) // Apple's limit, with headroom
        #expect(SiriBudget.total + SiriBudget.itemPhrases > SiriBudget.limit) // one more item each wouldn't fit: nothing wasted
    }
}
