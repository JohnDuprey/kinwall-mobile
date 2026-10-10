import AlarmKit
import AppIntents
import CryptoKit
import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Cooking timers that ring with the app in the background or closed. The web app's cooking
/// payload lists every running timer's finish (`alarms`, web/src/liveActivity.ts); the page stays
/// the source of truth and each payload replaces the last set. Pause, reset or cancel on the page
/// takes a timer out of the list, and resume puts it back with its new finish, so a timer is
/// known by its finish and title.
///
/// iOS 26 and later, once allowed: an AlarmKit alarm at each finish, so it rings like the Clock
/// app's timer, through silent mode and Focus. It's an alarm at a fixed time rather than an
/// AlarmKit countdown: the cooking Live Activity already counts down on the Lock Screen, so the
/// system shows only the alert, with Stop, and has no Pause that could fall out of step with the page.
/// Otherwise (iOS 17 to 25, or AlarmKit not allowed): a local notification at each finish.
/// A range ("5–6 min") also lists its check (`checks`): always a plain notification, one short
/// sound, never an alarm, since the timer keeps going. An app from before ranges ignores `checks`.
public enum CookingAlarms {
    /// The intent Stop runs, from the app target (native/ios/LiveActivityIntents.swift
    /// StopCookingTimerIntent, set at launch by AppHooks): App Intents have to live in the app itself.
    /// It ends the timer's Live Activity. `at`: the timer's finish, ms since 1970.
    nonisolated(unsafe) public static var stopIntent: ((Double) -> any LiveActivityIntent)?
    private struct Alarm: Decodable { let at: Double; let title: String; let body: String }
    private struct Payload: Decodable { let alarms: [Alarm]?; let checks: [Alarm]? }
    static let prefix = "cook:"
    @MainActor private static var last: Task<Void, Never>?

    /// The page's cooking payload (a page from before `alarms` rings nothing). `accent`: the family's
    /// accent color (#RRGGBB) for the alarm, or nil for Kinwall's.
    @MainActor static func set(json: String, accent: String? = nil) {
        let p = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        let tint = tint(accent)
        run { await apply(p?.alarms ?? [], checks: p?.checks ?? [], tint: tint) }
    }

    /// Cooking mode closed, or sign-out: nothing rings, and one that's ringing stops.
    @MainActor static func clear() { run { await apply(nil, checks: [], tint: tint(nil)) } }

    /// The family's accent, else Kinwall's own (web/src default scheme).
    private static func tint(_ hex: String?) -> Color {
        guard let hex, hex.count == 7, hex.first == "#", let v = Int(hex.dropFirst(), radix: 16) else { return Color(red: 0.647, green: 0.38, blue: 0.247) }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// One at a time, in order: payloads come quickly and each diff reads what the last one set.
    @MainActor private static func run(_ work: @escaping () async -> Void) {
        let before = last
        last = Task { await before?.value; await work() }
    }

    private static func apply(_ alarms: [Alarm]?, checks: [Alarm], tint: Color) async {
        let now = Date().timeIntervalSince1970
        var wanted: [UUID: Alarm] = [:]
        for a in alarms ?? [] where a.at / 1000 > now { wanted[id(a)] = a }
        var left = wanted
        if #available(iOS 26, *) { left = await ring(wanted, clearing: alarms == nil, tint: tint) }
        for c in checks where c.at / 1000 > now { left[id(c)] = c }
        await notify(left, clearing: alarms == nil)
    }

    /// The same timer gets the same id every time, so a payload that didn't change it leaves it be.
    private static func id(_ a: Alarm) -> UUID {
        let d = Array(SHA256.hash(data: Data("\(Int64(a.at))|\(a.title)".utf8)))
        return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15]))
    }

    // MARK: - AlarmKit (iOS 26)

    @available(iOS 26, *)
    private struct Meta: AlarmMetadata {}

    /// Sets the wanted alarms and takes away the rest; returns the ones AlarmKit didn't take (all of
    /// them when it isn't allowed). Asks the first time a timer runs.
    @available(iOS 26, *)
    private static func ring(_ wanted: [UUID: Alarm], clearing: Bool, tint: Color) async -> [UUID: Alarm] {
        let manager = AlarmManager.shared
        var state = manager.authorizationState
        if state == .notDetermined && !wanted.isEmpty { state = (try? await manager.requestAuthorization()) ?? .denied }
        // One that's ringing stays until Stop, unless cooking mode is on screen (the page beeps
        // itself, and marks the timer done) or it's closing.
        let onScreen = await MainActor.run { UIApplication.shared.applicationState == .active }
        let set = (try? manager.alarms) ?? []
        for alarm in set where wanted[alarm.id] == nil {
            if alarm.state != .alerting { try? manager.cancel(id: alarm.id) }
            else if onScreen || clearing { try? manager.stop(id: alarm.id); try? manager.cancel(id: alarm.id) }
        }
        guard state == .authorized else { return wanted }
        let have = Set(set.map(\.id))
        var left: [UUID: Alarm] = [:]
        for (id, a) in wanted where !have.contains(id) {
            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(String.LocalizationValue(a.title)), stopButton: stop)
            let attributes = AlarmAttributes<Meta>(presentation: AlarmPresentation(alert: alert), tintColor: tint)
            do { _ = try await manager.schedule(id: id, configuration: .alarm(schedule: .fixed(Date(timeIntervalSince1970: a.at / 1000)), attributes: attributes, stopIntent: stopIntent?(a.at))) }
            catch { left[id] = a } // e.g. too many alarms: a notification instead
        }
        return left
    }

    // MARK: - Notifications (iOS 17 to 25, or AlarmKit not allowed)

    /// Cancels every pending cooking notification and schedules these. The app hides them while
    /// it's open (src/reminders.ts), since cooking mode beeps itself.
    private static func notify(_ wanted: [UUID: Alarm], clearing: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        if clearing { center.removeDeliveredNotifications(withIdentifiers: await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }) }
        guard !wanted.isEmpty else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound]) // asks only if never asked (the demo)
        for (id, a) in wanted {
            let content = UNMutableNotificationContent()
            content.title = a.title
            content.body = a.body
            content.sound = .default
            content.threadIdentifier = "cooking"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, a.at / 1000 - Date().timeIntervalSince1970), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + id.uuidString, content: content, trigger: trigger))
        }
    }
}
