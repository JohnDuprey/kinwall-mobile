import Foundation

struct RoutineHours: Codable, Equatable {
    let start: String
    let cutoff: String
    static func minute(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.utf8.count == 2 && $0.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), hour < 24, minute < 60 else { return nil }
        return hour * 60 + minute
    }
    var isValid: Bool {
        guard let s = Self.minute(start), let e = Self.minute(cutoff) else { return false }
        return s < e
    }
}

struct RoutineInterval {
    let name: String
    let start: DateComponents
    let end: DateComponents
    let durationMinutes: Int
}

/// The saved household policy is independent of one day's chore approval. Foundation only:
/// the app, Device Activity extension and command-line regression tests compile this same file.
struct RoutineCalendar: Codable, Equatable {
    let timezone: String
    let start: String
    let cutoff: String
    let days: [RoutineHours?] // Sunday first, matching the server policy.
    let scheduleOnly: Bool // Only an explicit empty required-chore list grants future days.

    var isValid: Bool {
        TimeZone(identifier: timezone) != nil && RoutineHours(start: start, cutoff: cutoff).isValid
            && days.count == 7 && days.allSatisfy { $0?.isValid ?? true }
    }
    private var household: Calendar? {
        guard let zone = TimeZone(identifier: timezone) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar
    }
    private func instant(day: DateComponents, minute: Int, zone: TimeZone) -> Date? {
        // Match server/src/recurrence.ts zonedTimeToUtc, including repeated-clock resolution.
        // An absolute cutoff must not reopen when a daylight-saving clock moves backwards.
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let guess = utc.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: minute / 60, minute: minute % 60, second: 0)) else { return nil }
        let offset = zone.secondsFromGMT(for: guess)
        let first = guess.addingTimeInterval(-Double(offset))
        let nextOffset = zone.secondsFromGMT(for: first)
        return nextOffset == offset ? first : guess.addingTimeInterval(-Double(nextOffset))
    }
    func locked(at now: Date, decisionDate: String, decisionLocked: Bool, validUntil: Date) -> Bool {
        guard isValid, let calendar = household else { return true }
        let day = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let weekday = day.weekday, let year = day.year, let month = day.month, let date = day.day else { return true }
        let hours = days[weekday - 1] ?? RoutineHours(start: start, cutoff: cutoff)
        guard let s = RoutineHours.minute(hours.start), let e = RoutineHours.minute(hours.cutoff),
              let begins = instant(day: day, minute: s, zone: calendar.timeZone), let ends = instant(day: day, minute: e, zone: calendar.timeZone) else { return true }
        if now < begins { return false }
        if now >= ends { return true }
        if scheduleOnly { return false }
        let key = String(format: "%04d-%02d-%02d", year, month, date)
        return key != decisionDate || decisionLocked || now >= validUntil
    }
    func intervals() -> [RoutineInterval] {
        guard isValid, let calendar = household else { return [] }
        func components(_ weekday: Int?, _ minute: Int) -> DateComponents {
            var value = DateComponents()
            value.calendar = calendar; value.timeZone = calendar.timeZone
            if let weekday { value.weekday = (weekday - 1 + minute / 1440) % 7 + 1 }
            value.hour = (minute % 1440) / 60; value.minute = minute % 60; value.second = 0
            return value
        }
        func interval(_ name: String, _ weekday: Int?, _ start: Int, _ end: Int) -> RoutineInterval {
            let duration = max(16, end - start)
            return RoutineInterval(name: name, start: components(weekday, start), end: components(weekday, start + duration), durationMinutes: duration)
        }
        // Whole intervals cover first use after a boundary; short point-only windows can be
        // missed while a device is asleep. The daily interval also refreshes the household day.
        var plans = [interval("day", nil, 0, 1439)]
        for weekday in 1...7 {
            let hours = days[weekday - 1] ?? RoutineHours(start: start, cutoff: cutoff)
            let s = RoutineHours.minute(hours.start)!, e = RoutineHours.minute(hours.cutoff)!
            plans.append(interval("routine.\(weekday)", weekday, s, e))
            plans.append(interval("night.\(weekday)", weekday, e, 1440))
        }
        return plans
    }
}

struct RoutineCalendarSnapshot: Codable {
    let calendar: RoutineCalendar
    let decisionDate: String
    let decisionLocked: Bool
    let validUntil: Date
    let monitorsReady: Bool
    func locked(at now: Date) -> Bool {
        !monitorsReady || calendar.locked(at: now, decisionDate: decisionDate, decisionLocked: decisionLocked, validUntil: validUntil)
    }
}
