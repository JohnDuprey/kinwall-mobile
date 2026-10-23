import ExpoModulesCore
import FamilyControls
import SwiftUI
import UIKit

@MainActor enum RoutineMode {
    static var simulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    static func status() -> [String: Any] {
        if !simulator { RoutineEnforcement.expire() }
        let selection = RoutineEnforcement.selection
        return ["simulator": simulator, "authorized": simulator || AuthorizationCenter.shared.authorizationStatus == .approved,
                "appMode": RoutineEnforcement.defaults.string(forKey: "appMode") ?? "selected",
                "selected": simulator ? RoutineEnforcement.defaults.integer(forKey: "previewCount") : selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count,
                "allowedApps": simulator ? RoutineEnforcement.defaults.integer(forKey: "previewAllowedCount") : RoutineEnforcement.allowedSelection.applicationTokens.count, "allowedWebsitesOnly": RoutineEnforcement.defaults.bool(forKey: "allowedWebsitesOnly"),
                "locked": RoutineEnforcement.defaults.bool(forKey: "locked"), "memberId": RoutineEnforcement.defaults.string(forKey: "memberId") ?? ""]
    }
    static func apply(json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8), let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = raw["enabled"] as? Bool, let locked = raw["locked"] as? Bool,
              let cutoff = raw["validUntil"] as? String,
              let until = ISO8601DateFormatter.fractional.date(from: cutoff) ?? ISO8601DateFormatter().date(from: cutoff) else {
            throw Exception(name: "RoutineMode", description: "The routine decision could not be read.")
        }
        let appMode = raw["appMode"] as? String ?? "selected"
        guard appMode == "selected" || appMode == "all" else {
            throw Exception(name: "RoutineMode", description: "Choose a valid app mode.")
        }
        RoutineEnforcement.defaults.set(appMode, forKey: "appMode")
        let schoolOnly = raw["allowedWebsitesOnly"] as? Bool ?? false
        var domains = raw["allowedWebDomains"] as? [String] ?? []
        // The shell supplies the connected server's host, never a host claimed by the web page.
        if let host = raw["kinwallHost"] as? String, !host.isEmpty { domains.append(host) }
        RoutineEnforcement.defaults.set(schoolOnly, forKey: "allowedWebsitesOnly")
        RoutineEnforcement.defaults.set(domains, forKey: "allowedWebDomains")
        if simulator {
            RoutineEnforcement.defaults.set(enabled && (locked || until <= Date()), forKey: "locked")
        } else {
            guard AuthorizationCenter.shared.authorizationStatus == .approved else { return status() }
            try RoutineEnforcement.apply(enabled: enabled, locked: locked, until: until)
        }
        return status()
    }
    static func setup(memberId: String, appMode: String, websiteList: Bool) async throws -> [String: Any] {
        guard appMode == "selected" || appMode == "all" else {
            throw Exception(name: "RoutineMode", description: "Choose a valid app mode.")
        }
        if !simulator { try await AuthorizationCenter.shared.requestAuthorization(for: .child) }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            throw Exception(name: "RoutineMode", description: "Open Kinwall to choose apps.")
        }
        while let next = presenter.presentedViewController { presenter = next }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let controller = UIHostingController(rootView: RoutinePicker(simulator: simulator, appMode: appMode, websiteList: websiteList, save: { selected, allowed, count, allowedCount in
                RoutineEnforcement.defaults.set(appMode, forKey: "appMode")
                RoutineEnforcement.selection = selected
                RoutineEnforcement.allowedSelection = allowed
                RoutineEnforcement.defaults.set(memberId, forKey: "memberId")
                RoutineEnforcement.defaults.set(count, forKey: "previewCount")
                RoutineEnforcement.defaults.set(allowedCount, forKey: "previewAllowedCount")
                if !simulator && RoutineEnforcement.defaults.bool(forKey: "locked") { RoutineEnforcement.shield() }
                presenter.dismiss(animated: true) { continuation.resume() }
            }, cancel: { presenter.dismiss(animated: true) { continuation.resume() } }))
            controller.isModalInPresentation = true
            presenter.present(controller, animated: true)
        }
        return status()
    }
}
private struct RoutinePicker: View {
    let simulator: Bool
    let appMode: String
    let websiteList: Bool
    let save: (FamilyActivitySelection, FamilyActivitySelection, Int, Int) -> Void
    let cancel: () -> Void
    @State private var selected = RoutineEnforcement.selection
    @State private var allowed = RoutineEnforcement.allowedSelection
    @State private var keepingAvailable = false
    @State private var browserAllowed = true
    @State private var games = true
    @State private var videos = true
    @State private var readingAllowed = true
    @State private var calculatorAllowed = false
    var body: some View {
        NavigationStack {
            Group {
                if simulator {
                    Form {
                        Section("Simulator preview") {
                            Text("Apple Screen Time enforcement needs a physical child device. These choices preview the flow only.")
                            Text(appMode == "all" ? "All apps are paused except allowed apps. Kinwall stays available." : "Pause categories, individual apps, or a combination. Allowed apps take priority.")
                            if appMode == "selected" {
                                Toggle("Pause Games category", isOn: $games)
                                Toggle("Pause Video player app", isOn: $videos)
                            }
                            Toggle("Keep Reading app available", isOn: $readingAllowed)
                            Toggle("Keep Calculator available", isOn: $calculatorAllowed)
                            if websiteList { Text("Safari stays available for allowed websites in this preview. On a real device, select Safari in Keep available.") }
                            else { Toggle("Keep Safari available", isOn: $browserAllowed) }
                        }
                    }
                } else {
                    VStack {
                        if appMode == "selected" {
                            Picker("Choose apps", selection: $keepingAvailable) {
                                Text("Pause").tag(false)
                                Text("Keep available").tag(true)
                            }.pickerStyle(.segmented).padding(.horizontal)
                        }
                        if appMode == "all" {
                            Text("All apps are paused except the apps you keep available. Kinwall stays available automatically.").font(.footnote).padding(.horizontal)
                        }
                        Text((keepingAvailable || appMode == "all") ? "Choose individual apps such as Safari, your school browser and essential tools. When Only allowed websites is on, include Safari or your school browser here. Allowed website rules still apply in the browser." : "Choose entertainment apps and categories to pause until the routine is complete. Configure allowed websites in Settings.")
                            .font(.footnote).padding(.horizontal)
                        FamilyActivityPicker(selection: (keepingAvailable || appMode == "all") ? $allowed : $selected)
                        if appMode == "selected" && !selected.webDomainTokens.isEmpty {
                            Text("Choose apps and categories here. Configure allowed websites in Settings.").font(.footnote).padding()
                        }
                        if !allowed.categoryTokens.isEmpty || !allowed.webDomainTokens.isEmpty {
                            Text("Under Keep available, choose individual apps rather than categories or websites.").font(.footnote).padding()
                        }
                    }
                }
            }
            .navigationTitle("Routine apps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(selected, allowed, (games ? 1 : 0) + (videos ? 1 : 0), (websiteList || browserAllowed ? 1 : 0) + (readingAllowed ? 1 : 0) + (calculatorAllowed ? 1 : 0)) }
                        .disabled(!simulator && ((appMode == "selected" && !selected.webDomainTokens.isEmpty) || !allowed.categoryTokens.isEmpty || !allowed.webDomainTokens.isEmpty)) }
            }
        }
    }
}
private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }
}
