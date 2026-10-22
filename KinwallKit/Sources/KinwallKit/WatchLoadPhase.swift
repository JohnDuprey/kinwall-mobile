/// Request completion is independent of whether the response contains any rows.
public enum WatchLoadPhase: Sendable {
    case loading
    case loaded
    case failed

    public static func completing(_ operation: () async throws -> Void) async -> Self {
        do {
            try await operation()
            return .loaded
        } catch {
            return .failed
        }
    }
}
