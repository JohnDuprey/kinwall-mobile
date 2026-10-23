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
                "locked": RoutineEnforcement.defaults.bool(forKey: "locked"), "memberId": RoutineEnforcement.defaults.string(forKey: "memberId") ?? "",
                "server": RoutineEnforcement.defaults.string(forKey: "server") ?? "",
                "appliedRevision": RoutineEnforcement.defaults.integer(forKey: "selectionRevision"),
                "hasAppChoices": RoutineEnforcement.defaults.object(forKey: "previewCount") != nil || RoutineEnforcement.defaults.integer(forKey: "selectionRevision") > 0,
                "remoteSelection": true]
    }
    // Child authorization and guardian app selection are separate Apple flows. A guardian's
    // picker lists authorized child devices in their Family Sharing group without requesting
    // .child authorization on the guardian's own phone.
    static func authorize(memberId: String, server: String) async throws -> [String: Any] {
        if !simulator { try await AuthorizationCenter.shared.requestAuthorization(for: .child) }
        if RoutineEnforcement.defaults.string(forKey: "memberId") != memberId || RoutineEnforcement.defaults.string(forKey: "server") != server {
            for key in ["selectionRevision", "selection", "allowedSelection", "previewCount", "previewAllowedCount"] { RoutineEnforcement.defaults.removeObject(forKey: key) }
            if !simulator { try RoutineEnforcement.apply(enabled: false, locked: false, until: Date()) }
        }
        RoutineEnforcement.defaults.set(memberId, forKey: "memberId")
        RoutineEnforcement.defaults.set(server, forKey: "server")
        return status()
    }
    private static func transfer(_ encoded: String) throws -> RoutineSelectionTransfer {
        guard encoded.utf8.count <= 174764, let data = Data(base64Encoded: encoded), data.count <= 131072,
              let value = try? JSONDecoder().decode(RoutineSelectionTransfer.self, from: data), value.version == 1 else {
            throw Exception(name: "RoutineMode", description: "The saved app choices could not be read. Choose apps again.")
        }
        guard simulator || value.preview == nil else {
            throw Exception(name: "RoutineMode", description: "Simulator choices cannot be used on a child’s device.")
        }
        guard value.allowed.categoryTokens.isEmpty, value.allowed.webDomainTokens.isEmpty, value.selected.webDomainTokens.isEmpty else {
            throw Exception(name: "RoutineMode", description: "Choose apps and categories to pause, and individual apps to keep available.")
        }
        return value
    }
    static func importSelection(memberId: String, server: String, encoded: String, revision: Int) throws -> [String: Any] {
        guard revision > 0, RoutineEnforcement.defaults.string(forKey: "memberId") == memberId,
              RoutineEnforcement.defaults.string(forKey: "server") == server,
              simulator || AuthorizationCenter.shared.authorizationStatus == .approved else {
            throw Exception(name: "RoutineMode", description: "Approve Screen Time on this child’s device before receiving app choices.")
        }
        let value = try transfer(encoded)
        RoutineEnforcement.selection = value.selected
        RoutineEnforcement.allowedSelection = value.allowed
        RoutineEnforcement.defaults.set(revision, forKey: "selectionRevision")
        if let preview = value.preview {
            RoutineEnforcement.defaults.set(preview.selectedApps + preview.selectedCategories, forKey: "previewCount")
            RoutineEnforcement.defaults.set(preview.allowedApps, forKey: "previewAllowedCount")
        }
        if RoutineEnforcement.defaults.bool(forKey: "enabled") && RoutineEnforcement.defaults.bool(forKey: "locked") && !simulator { RoutineEnforcement.shield() }
        return status()
    }
    static func choose(memberId: String, appMode: String, websiteList: Bool, encoded: String?) async throws -> [String: Any] {
        guard appMode == "selected" || appMode == "all" else {
            throw Exception(name: "RoutineMode", description: "Choose a valid app mode.")
        }
        let previous = try encoded.map { try transfer($0) }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            throw Exception(name: "RoutineMode", description: "Open Kinwall to choose apps.")
        }
        while let next = presenter.presentedViewController { presenter = next }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            let picker = RoutinePicker(simulator: simulator, appMode: appMode, websiteList: websiteList,
                initialSelected: previous?.selected ?? FamilyActivitySelection(includeEntireCategory: true),
                initialAllowed: previous?.allowed ?? FamilyActivitySelection(), initialPreview: previous?.preview ?? RoutinePreview(),
                save: { selected, allowed, preview in
                    do {
                        let value = RoutineSelectionTransfer(version: 1, selected: selected, allowed: allowed, preview: simulator ? preview : nil)
                        let data = try JSONEncoder().encode(value).base64EncodedString()
                        // No local enforcement state is changed on a guardian's device.
                        let result: [String: Any] = ["data": data,
                            "selectedApps": simulator ? preview.selectedApps : selected.applicationTokens.count,
                            "selectedCategories": simulator ? preview.selectedCategories : selected.categoryTokens.count,
                            "allowedApps": simulator ? preview.allowedApps : allowed.applicationTokens.count]
                        presenter.dismiss(animated: true) { continuation.resume(returning: result) }
                    } catch { presenter.dismiss(animated: true) { continuation.resume(throwing: error) } }
                }, cancel: { presenter.dismiss(animated: true) { continuation.resume(returning: ["cancelled": true]) } })
            let controller = UIHostingController(rootView: picker)
            controller.isModalInPresentation = true
            presenter.present(controller, animated: true)
        }
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
            let controller = UIHostingController(rootView: RoutinePicker(simulator: simulator, appMode: appMode, websiteList: websiteList, save: { selected, allowed, preview in
                RoutineEnforcement.defaults.set(appMode, forKey: "appMode")
                RoutineEnforcement.selection = selected
                RoutineEnforcement.allowedSelection = allowed
                RoutineEnforcement.defaults.set(memberId, forKey: "memberId")
                RoutineEnforcement.defaults.set(preview.selectedApps + preview.selectedCategories, forKey: "previewCount")
                RoutineEnforcement.defaults.set(preview.allowedApps, forKey: "previewAllowedCount")
                if !simulator && RoutineEnforcement.defaults.bool(forKey: "locked") { RoutineEnforcement.shield() }
                presenter.dismiss(animated: true) { continuation.resume() }
            }, cancel: { presenter.dismiss(animated: true) { continuation.resume() } }))
            controller.isModalInPresentation = true
            presenter.present(controller, animated: true)
        }
        return status()
    }
}
private struct RoutineSelectionTransfer: Codable {
    let version: Int
    let selected: FamilyActivitySelection
    let allowed: FamilyActivitySelection
    let preview: RoutinePreview?
}
private struct RoutinePreview: Codable {
    var games = true
    var videos = true
    var reading = true
    var calculator = false
    var browser = true
    var selectedApps: Int { videos ? 1 : 0 }
    var selectedCategories: Int { games ? 1 : 0 }
    var allowedApps: Int { (reading ? 1 : 0) + (calculator ? 1 : 0) + (browser ? 1 : 0) }
}
private struct RoutinePicker: View {
    let simulator: Bool
    let appMode: String
    let websiteList: Bool
    let save: (FamilyActivitySelection, FamilyActivitySelection, RoutinePreview) -> Void
    let cancel: () -> Void
    @State private var selected: FamilyActivitySelection
    @State private var allowed: FamilyActivitySelection
    @State private var keepingAvailable = false
    @State private var browserAllowed = true
    @State private var games = true
    @State private var videos = true
    @State private var readingAllowed = true
    @State private var calculatorAllowed = false
    init(simulator: Bool, appMode: String, websiteList: Bool,
         initialSelected: FamilyActivitySelection = RoutineEnforcement.selection,
         initialAllowed: FamilyActivitySelection = RoutineEnforcement.allowedSelection,
         initialPreview: RoutinePreview = RoutinePreview(),
         save: @escaping (FamilyActivitySelection, FamilyActivitySelection, RoutinePreview) -> Void, cancel: @escaping () -> Void) {
        self.simulator = simulator; self.appMode = appMode; self.websiteList = websiteList
        self.save = save; self.cancel = cancel
        _selected = State(initialValue: initialSelected); _allowed = State(initialValue: initialAllowed)
        _games = State(initialValue: initialPreview.games); _videos = State(initialValue: initialPreview.videos)
        _readingAllowed = State(initialValue: initialPreview.reading); _calculatorAllowed = State(initialValue: initialPreview.calculator)
        _browserAllowed = State(initialValue: initialPreview.browser)
    }
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
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(selected, allowed, RoutinePreview(games: games, videos: videos, reading: readingAllowed, calculator: calculatorAllowed, browser: websiteList || browserAllowed)) }
                        .disabled(!simulator && ((appMode == "selected" && !selected.webDomainTokens.isEmpty) || !allowed.categoryTokens.isEmpty || !allowed.webDomainTokens.isEmpty)) }
            }
        }
    }
}
private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }
}
