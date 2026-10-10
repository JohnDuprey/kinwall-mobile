import Foundation

/// The cooking timer Live Activity's headline and countdown at a moment. A single time counts to
/// its end under its name. A range ("5–6 min", web/src/liveActivity.ts `check`) counts to its check
/// with the web app's `before` words ("Check at 5:00"), then to its end with `after` ("Check now ·
/// up to 1:00 more"). Past the end, or rung: "Done: Rice" and no countdown.
public struct CookingLine: Equatable, Sendable {
    public let headline: String
    /// What the countdown counts to; nil once it's done.
    public let countdownTo: Date?

    public init(title: String, end: Date?, done: Bool, check: Date?, before: String?, after: String?, now: Date) {
        guard !done, let end, end > now else { headline = "Done: \(title)"; countdownTo = nil; return }
        if let check, check > now { headline = before ?? title; countdownTo = check }
        else if check != nil { headline = after ?? title; countdownTo = end }
        else { headline = title; countdownTo = end }
    }
}
