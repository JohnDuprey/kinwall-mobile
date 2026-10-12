import Foundation

/// The cooking timer Live Activity's headline and countdown. It always counts to the end, so it
/// never needs a redraw partway: iOS doesn't reliably redraw an activity at its stale date, and a
/// countdown to a range's check froze at 0:00 there. A range ("5–6 min", web/src/liveActivity.ts
/// `check`) says when to check in the same terms as the countdown: "Check with 1:00 left" (its
/// check notification rings then). A single time counts under its name. Past the end, or rung:
/// "Done: Rice" and no countdown.
public struct CookingLine: Equatable, Sendable {
    public let headline: String
    /// What the countdown counts to; nil once it's done.
    public let countdownTo: Date?

    public init(title: String, end: Date?, done: Bool, check: Date?, now: Date) {
        guard !done, let end, end > now else { headline = "Done: \(title)"; countdownTo = nil; return }
        countdownTo = end
        guard let check, check < end else { headline = title; return }
        let left = Int(end.timeIntervalSince(check).rounded())
        headline = "Check with \(left / 60):\(String(format: "%02d", left % 60)) left"
    }
}
