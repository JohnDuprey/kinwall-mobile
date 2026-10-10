import Foundation
import Testing
@testable import KinwallKit

@Suite struct CookingLineTests {
    let start = Date(timeIntervalSince1970: 0)
    func at(_ s: Double, done: Bool = false, check: Double? = 300) -> CookingLine {
        CookingLine(title: "Rice", end: start.addingTimeInterval(360), done: done, check: check.map { start.addingTimeInterval($0) },
                    before: check == nil ? nil : "Check at 5:00", after: check == nil ? nil : "Check now · up to 1:00 more", now: start.addingTimeInterval(s))
    }
    @Test func rangeCountsToTheCheckThenTheEnd() {
        #expect(at(60).headline == "Check at 5:00" && at(60).countdownTo == start.addingTimeInterval(300))
        #expect(at(300).headline == "Check now · up to 1:00 more" && at(300).countdownTo == start.addingTimeInterval(360))
        #expect(at(360).headline == "Done: Rice" && at(360).countdownTo == nil)
        #expect(at(10, done: true).headline == "Done: Rice")
    }
    @Test func singleTimeAsBefore() {
        #expect(at(60, check: nil).headline == "Rice" && at(60, check: nil).countdownTo == start.addingTimeInterval(360))
        #expect(at(400, check: nil).headline == "Done: Rice")
    }
}
