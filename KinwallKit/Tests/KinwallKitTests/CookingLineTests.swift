import Foundation
import Testing
@testable import KinwallKit

@Suite struct CookingLineTests {
    let start = Date(timeIntervalSince1970: 0)
    func at(_ s: Double, done: Bool = false, check: Double? = 300) -> CookingLine {
        CookingLine(title: "Rice", end: start.addingTimeInterval(360), done: done, check: check.map { start.addingTimeInterval($0) }, now: start.addingTimeInterval(s))
    }
    @Test func rangeCountsToTheEndAndSaysWhenToCheck() {
        // The same words and countdown before and after the check: nothing has to redraw.
        for s in [60.0, 300, 330] { #expect(at(s).headline == "Check with 1:00 left" && at(s).countdownTo == start.addingTimeInterval(360)) }
        #expect(at(360).headline == "Done: Rice" && at(360).countdownTo == nil)
        #expect(at(10, done: true).headline == "Done: Rice")
    }
    @Test func singleTimeAsBefore() {
        #expect(at(60, check: nil).headline == "Rice" && at(60, check: nil).countdownTo == start.addingTimeInterval(360))
        #expect(at(400, check: nil).headline == "Done: Rice")
    }
}
