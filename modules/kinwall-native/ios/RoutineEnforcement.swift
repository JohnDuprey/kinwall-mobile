import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

// Compiled into the app's native module and the monitor extension. Only opaque Apple tokens
// and the saved calendar/grant live in the shared group; no family credentials or chore details.
enum RoutineEnforcement {
    static let group = "group.family.kinwall.routine"
    static var defaults: UserDefaults { UserDefaults(suiteName: group)! }
    static let store = ManagedSettingsStore(named: .init("kinwall.routine"))
    static let monitor = DeviceActivityName("kinwall.routine.cutoff")
    private static let calendarPrefix = "kinwall.routine.calendar."
    private static let snapshotKey = "calendarSnapshot"
    private static let configuredKey = "configuredCalendar"
    static var selection: FamilyActivitySelection {
        get { defaults.data(forKey: "selection").flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "selection") }
    }
    static var allowedSelection: FamilyActivitySelection {
        get { defaults.data(forKey: "allowedSelection").flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "allowedSelection") }
    }
    static func shield() {
        let selected = selection
        let allowed = allowedSelection.applicationTokens
        let paused = selected.applicationTokens.subtracting(allowed)
        let allApps = defaults.string(forKey: "appMode") == "all"
        store.shield.applications = allApps || paused.isEmpty ? nil : paused
        if allApps {
            // Apple exempts the containing app from .all. Explicit exceptions override categories.
            store.shield.applicationCategories = .all(except: allowed)
        } else {
            store.shield.applicationCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens, except: allowed)
        }
        // Website permissions come exclusively from the allowed-websites setting.
        store.shield.webDomains = nil
        if defaults.bool(forKey: "allowedWebsitesOnly") {
            let domains = Set((defaults.stringArray(forKey: "allowedWebDomains") ?? []).map { WebDomain(domain: $0) })
            store.webContent.blockedByFilter = .all(except: domains)
        } else {
            store.webContent.blockedByFilter = nil
        }
        defaults.set(true, forKey: "locked")
    }
    static func clear() { store.clearAllSettings(); defaults.set(false, forKey: "locked") }
    static func expire() {
        guard defaults.bool(forKey: "enabled") else { return }
        if let data = defaults.data(forKey: snapshotKey) {
            guard let snapshot = try? JSONDecoder().decode(RoutineCalendarSnapshot.self, from: data) else { shield(); return }
            if snapshot.locked(at: Date()) { shield() } else { clear() }
            return
        }
        if let cutoff = defaults.object(forKey: "validUntil") as? Date, cutoff > Date() { return }
        shield()
    }
    private static func save(_ snapshot: RoutineCalendarSnapshot) throws {
        defaults.set(try JSONEncoder().encode(snapshot), forKey: snapshotKey)
    }
    private static func install(_ calendar: RoutineCalendar, center: DeviceActivityCenter) throws {
        let plans = calendar.intervals()
        let names = plans.map { DeviceActivityName(calendarPrefix + $0.name) }
        let previous = defaults.data(forKey: configuredKey).flatMap { try? JSONDecoder().decode(RoutineCalendar.self, from: $0) }
        if previous == calendar && Set(names).isSubset(of: Set(center.activities)) { return }
        for (plan, name) in zip(plans, names) {
            try center.startMonitoring(name, during: DeviceActivitySchedule(intervalStart: plan.start, intervalEnd: plan.end, repeats: true))
        }
        defaults.set(try JSONEncoder().encode(calendar), forKey: configuredKey)
    }
    private static func installExpiry(_ until: Date, center: DeviceActivityCenter) throws {
        if defaults.object(forKey: "scheduledExpiry") as? Date == until && center.activities.contains(monitor) { return }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute, .second], from: until)
        let end = calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute, .second], from: until.addingTimeInterval(16 * 60))
        try center.startMonitoring(monitor, during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false))
        defaults.set(until, forKey: "scheduledExpiry")
    }
    static func apply(enabled: Bool, locked: Bool, until: Date, calendar: RoutineCalendar? = nil, decisionDate: String? = nil) throws {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(until, forKey: "validUntil")
        let center = DeviceActivityCenter()
        if !enabled {
            center.stopMonitoring(center.activities.filter { $0 == monitor || $0.rawValue.hasPrefix(calendarPrefix) })
            for key in [snapshotKey, configuredKey, "scheduledExpiry"] { defaults.removeObject(forKey: key) }
            clear(); return
        }
        if let calendar {
            guard calendar.isValid, let decisionDate else { shield(); throw NSError(domain: "KinwallRoutine", code: 1, userInfo: [NSLocalizedDescriptionKey: "The routine schedule could not be read."]) }
            // Installing all callbacks comes before granting access. A partial installation
            // remains explicitly fail-closed and will be retried on the next server check.
            try save(RoutineCalendarSnapshot(calendar: calendar, decisionDate: decisionDate, decisionLocked: locked, validUntil: until, monitorsReady: false))
            do {
                try install(calendar, center: center)
                if !locked && until > Date() { try installExpiry(until, center: center) }
                try save(RoutineCalendarSnapshot(calendar: calendar, decisionDate: decisionDate, decisionLocked: locked, validUntil: until, monitorsReady: true))
                expire()
            } catch { shield(); throw error }
            return
        }
        // Older servers still use the original absolute, one-day grant.
        center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(calendarPrefix) })
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: configuredKey)
        if locked || until <= Date() { shield(); return }
        // Install the local expiry BEFORE granting access. A failed schedule leaves apps blocked.
        // The 15-minute monitoring interval begins at the cutoff, so even a short grant can expire.
        do {
            try installExpiry(until, center: center)
            clear()
        } catch { shield(); throw error }
    }
}
