/// A completed request with no active lists is different from the initial loading state.
public enum WatchListsState: Sendable {
    case loading
    case loaded([FamilyList])
    case failed
    case off

    public var lists: [FamilyList] {
        guard case .loaded(let lists) = self else { return [] }
        return lists.filter { !$0.archived }
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var isEmpty: Bool {
        if case .loaded = self { return lists.isEmpty }
        return false
    }
}
