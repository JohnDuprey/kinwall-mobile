import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

// Compiled into the app's native module and the monitor extension. Only opaque Apple tokens
// and the cutoff live in the shared group; no family credentials or chore details.
enum RoutineEnforcement {
    static let group = "group.family.kinwall.routine"
    static var defaults: UserDefaults { UserDefaults(suiteName: group)! }
    static let store = ManagedSettingsStore(named: .init("kinwall.routine"))
    static let monitor = DeviceActivityName("kinwall.routine.cutoff")
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
        if let cutoff = defaults.object(forKey: "validUntil") as? Date, cutoff > Date() { return }
        shield()
    }
    static func apply(enabled: Bool, locked: Bool, until: Date) throws {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(until, forKey: "validUntil")
        let center = DeviceActivityCenter()
        if !enabled { center.stopMonitoring([monitor]); clear(); return }
        if locked || until <= Date() { shield(); return }
        // Install the local expiry BEFORE granting access. A failed schedule leaves apps blocked.
        // The 15-minute monitoring interval begins at the cutoff, so even a short grant can expire.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute, .second], from: until)
        let end = calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute, .second], from: until.addingTimeInterval(16 * 60))
        do {
            try center.startMonitoring(monitor, during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false))
            clear()
        } catch { shield(); throw error }
    }
}
