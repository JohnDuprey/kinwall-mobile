import Foundation

/// The main actor can re-enter while ActivityKit is ending or updating a card. Keep event
/// starts, updates, and cleanup in one queue, including activities delivered by Apple push.
@MainActor final class EventActivityCoordinator {
    private var pending: Task<Void, Never>?

    func perform(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = pending
        let next = Task { @MainActor in
            await previous?.value
            try await operation()
        }
        pending = Task { _ = try? await next.value }
        try await next.value
    }

    struct Candidate {
        let id: String
        let activity: String?
        let running: Bool
    }

    /// ActivityKit enumeration order is unspecified. Every callback must pick the same live
    /// instance, and an ended card still visible on the Lock Screen must never be kept.
    static func keeper(_ candidates: [Candidate], preferred: String?) -> String? {
        let running = candidates.filter { $0.running }
        let matching = preferred.map { key in running.filter { $0.activity == key } } ?? running
        return (matching.isEmpty ? running : matching).map(\.id).sorted().first
    }
}
