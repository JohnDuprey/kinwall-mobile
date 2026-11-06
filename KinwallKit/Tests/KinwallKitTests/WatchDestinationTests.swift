import Foundation
import Testing
@testable import KinwallKit

@Suite struct WatchDestinationTests {
    @Test func takeNowWidgetOpensMedicinePage() {
        #expect(WatchDestination(url: URL(string: "family.kinwall.app:/open?to=medications")!) == .medicines)
    }
    @Test func widgetLinksSelectTheirOwnPage() {
        #expect(WatchDestination(url: URL(string: "family.kinwall.app:/open?to=chores")!) == .chores)
        #expect(WatchDestination(url: URL(string: "family.kinwall.app:/open?to=home")!) == .today)
    }
    @Test func unrelatedLinksDoNotChangePages() {
        for text in ["https://example.com/open?to=medications", "family.kinwall.app:/other?to=medications", "family.kinwall.app:/open?to=unknown"] {
            #expect(WatchDestination(url: URL(string: text)!) == nil)
        }
    }
    @Test func medicineTimesHandleServerFractionalSeconds() {
        for timestamp in ["2030-03-04T08:00:00.000Z", "2030-03-04T08:00:00Z"] {
            let dose = DueDose(medicationId: "med1", memberId: "m2", date: "2030-03-04", time: "08:00", dueAt: timestamp, name: nil, dose: nil)
            #expect(dose.dueDate == ISO8601DateFormatter().date(from: "2030-03-04T08:00:00Z"))
        }
    }

    @Test func widgetActionsDoNotKeepMedicineNames() {
        let dose = DueDose(medicationId: "med1", memberId: "m2", date: "2030-03-04", time: "08:00", dueAt: "2030-03-04T08:00:00Z", name: "Private medicine", dose: "1 tablet")
        let widgetDose = dose.withoutMedicineNames
        #expect(widgetDose.id == dose.id && widgetDose.memberId == dose.memberId && widgetDose.dueAt == dose.dueAt)
        #expect(widgetDose.name == nil && widgetDose.dose == nil)
    }

}
