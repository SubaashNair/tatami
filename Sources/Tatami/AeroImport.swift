import AppKit
import SwiftUI
import TatamiCore

/// What the import sheet shows: the plan, and the Room name to use for each AeroSpace workspace.
struct AeroImportDraft: Identifiable {
    let id = UUID()
    let plan: AeroImportPlan
    var roomNames: [String: String]
}

extension AppModel {
    /// Asks for an AeroSpace config (default ~/.aerospace.toml), reads its `on-window-detected` rules, and shows a preview.
    func chooseAeroSpaceConfig() {
        let panel = NSOpenPanel()
        panel.message = "Choose your AeroSpace config (usually ~/.aerospace.toml)"
        panel.prompt = "Read Config"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 1_000_000, let text = try? String(contentsOf: url, encoding: .utf8) else { error = "Could not read \(url.lastPathComponent) (it must be a text file under 1 MB)."; return }
        let rules = AeroSpaceConfig.parse(text)
        guard !rules.isEmpty else { error = "That file has no on-window-detected rules to import."; return }
        notice = "Reading your installed apps…"
        Task {
            let apps = await Task.detached { Self.installedApps() }.value  // scanning folders and matching names stays off the main thread
            let plan = AeroImport.plan(rules, installed: apps)
            notice = nil
            guard !plan.entries.isEmpty else { error = "Nothing to import. " + (plan.skipped.first ?? ""); return }
            aeroImport = AeroImportDraft(plan: plan, roomNames: Dictionary(uniqueKeysWithValues: plan.rooms.map { ($0, "Workspace \($0)") }))
        }
    }

    func finishAeroImport(_ draft: AeroImportDraft) {
        undoSnapshot = snapshot(name: "Before importing AeroSpace rules")
        let result = state.applyAeroImport(draft.plan, roomNames: draft.roomNames)
        persist()
        publish()
        aeroImport = nil
        var parts = ["Imported \(result.rulesAdded) routing rule(s)"]
        if !result.roomsCreated.isEmpty { parts.append("\(result.roomsCreated.count) new Room(s)") }
        if result.floatRulesAdded > 0 { parts.append("\(result.floatRulesAdded) float rule(s)") }
        if result.keptExisting > 0 { parts.append("\(result.keptExisting) app(s) kept their own rule") }
        if !result.skipped.isEmpty { parts.append("\(result.skipped.count) skipped") }
        notice = parts.joined(separator: ", ") + ". Undo removes the new Rooms and their routing rules."
    }

    /// Apps in the usual folders (and the running ones), under every name AeroSpace might match: display name, bundle name,
    /// and file name. Running apps add their localized name.
    nonisolated static func installedApps() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", home + "/Applications"]
        var bundles: [URL] = []
        for folder in folders {
            let url = URL(fileURLWithPath: folder)
            let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                if item.pathExtension == "app" { bundles.append(item) }
                else if folder.hasSuffix("/Applications"), item.hasDirectoryPath {  // one level down, e.g. a vendor folder
                    bundles += ((try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
                }
            }
        }
        for url in bundles {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let names = [bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                         bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                         url.deletingPathExtension().lastPathComponent].compactMap { $0 }
            for name in Set(names) { apps.append(InstalledApp(bundleID: id, name: name)) }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, let name = app.localizedName { apps.append(InstalledApp(bundleID: id, name: name)) }
        }
        return apps
    }
}

/// Preview of an AeroSpace import: name each workspace's Room, see the apps it would route, then import.
struct AeroImportSheet: View {
    @ObservedObject var model: AppModel
    @State var draft: AeroImportDraft

    private var problem: String? { AeroImport.nameProblem(plan: draft.plan, roomNames: draft.roomNames) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from AeroSpace").font(.system(size: 24, weight: .medium, design: .serif))
            if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(.red) }
            Text("Each workspace becomes a Room, and each app that its rules send there gets a routing rule. Name the Rooms below. Nothing changes until you import. Undo removes the new Rooms and their routing rules.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(draft.plan.rooms, id: \.self) { key in
                        let apps = draft.plan.entries.filter { $0.workspace == key }.flatMap(\.apps)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Workspace \(key)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).frame(width: 96, alignment: .leading)
                                TextField("Room name", text: Binding(get: { draft.roomNames[key] ?? "" }, set: { draft.roomNames[key] = $0 })).textFieldStyle(.roundedBorder)
                            }
                            Text(apps.isEmpty ? "No installed app matches" : apps.map(\.name).sorted().joined(separator: ", "))
                                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(3)
                        }
                    }
                    if !draft.plan.skipped.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skipped").font(.system(size: 11, weight: .semibold))
                            ForEach(draft.plan.skipped, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }.frame(maxHeight: 340)
            HStack {
                Button("Cancel") { model.aeroImport = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import") { model.finishAeroImport(draft) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }.padding(32).frame(width: 560)
    }
}
