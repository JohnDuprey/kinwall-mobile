import Foundation

/// Widget taps open the relevant Watch page; unknown links leave the current page alone.
public enum WatchDestination: Hashable, Sendable {
    case today, chores, checkIn, medicines, lists

    public init?(url: URL) {
        guard url.scheme == "family.kinwall.app", url.path == "/open",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let route = parts.queryItems?.first(where: { $0.name == "to" })?.value else { return nil }
        switch route {
        case "home": self = .today
        case "chores": self = .chores
        case "checkin": self = .checkIn
        case "medications": self = .medicines
        case "lists": self = .lists
        default: return nil
        }
    }

    public static let medicinesURL = URL(string: "family.kinwall.app:/open?to=medications")!
}
