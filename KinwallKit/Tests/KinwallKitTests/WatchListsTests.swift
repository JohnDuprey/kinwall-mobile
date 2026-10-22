import Testing
@testable import KinwallKit

@Suite struct WatchListsTests {
    @Test func noListsFinishesLoading() {
        var state = WatchListsState.loading
        #expect(state.isLoading)
        state = .loaded([])
        #expect(!state.isLoading)
        #expect(state.isEmpty)
    }

    @Test func onlyArchivedListsIsEmpty() {
        let archived = FamilyList(id: "archived", name: "Old list", emoji: nil, kind: .todo,
                                  archived: true, itemCount: 0, openCount: 0, catalog: nil, isDefault: nil)
        let state = WatchListsState.loaded([archived])
        #expect(!state.isLoading)
        #expect(state.isEmpty)
        #expect(state.lists.isEmpty)
    }

    @Test func activeListsStayVisible() {
        let list = FamilyList(id: "active", name: "Groceries", emoji: nil, kind: .shopping,
                              archived: false, itemCount: 1, openCount: 1, catalog: nil, isDefault: nil)
        let state = WatchListsState.loaded([list])
        #expect(!state.isLoading)
        #expect(!state.isEmpty)
        #expect(state.lists == [list])
    }

    @Test func failureAndDisabledAreNotLoadingOrEmpty() {
        for state in [WatchListsState.failed, .off] {
            #expect(!state.isLoading)
            #expect(!state.isEmpty)
        }
    }
}
