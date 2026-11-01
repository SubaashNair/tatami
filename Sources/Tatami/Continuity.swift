import AppKit
import ServiceManagement
import TatamiCore

/// Workspace continuity (M1 decision 13): which Stage each window belongs to survives quits, crashes, and reboots.
extension AppModel {
    var checkpointURL: URL { directory.appendingPathComponent("checkpoint.json") }
    private static let checkpointDelay: TimeInterval = 1

    func scheduleCheckpoint() {
        checkpointWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.writeCheckpoint() } }
        checkpointWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.checkpointDelay, execute: work)
    }

    func writeCheckpoint() {
        checkpointWork?.cancel()
        guard service.trusted, !service.windows.isEmpty else { return }  // never overwrite a good checkpoint with an empty scan
        let numbers = Dictionary(service.windows.map { ($0.id, $0.windowNumber) }, uniquingKeysWith: { a, _ in a })
        let checkpoint = Checkpoint(
            activeStageID: state.activeStageID,
            lastFocused: lastFocused.compactMapValues { numbers[$0] ?? nil },
            windows: service.windows.map { window in
                CheckpointWindow(windowNumber: window.windowNumber, pid: window.pid, bundleID: window.bundleID, title: window.title,
                                 frame: Rect(window.realFrame), stageID: window.stageID, displayKey: service.display(for: window.realFrame)?.id, id: window.id)
            },
            layouts: savedLayouts())
        do { try JSONEncoder().encode(checkpoint).write(to: checkpointURL, options: .atomic) }
        catch { self.error = "Could not save the workspace checkpoint: \(error.localizedDescription)" }
    }

    /// Re-attach windows to their Stages after Tatami (or the Mac) restarts. Frames are the journal's job.
    func restoreCheckpoint() {
        guard let data = try? Data(contentsOf: checkpointURL), let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data) else { return }
        let stageIDs = Set(state.stages.map(\.id))
        let live = service.windows.map { LiveWindowKey(windowNumber: $0.windowNumber, pid: $0.pid, bundleID: $0.bundleID, title: $0.title) }
        var restored = 0
        var idMap: [UUID: UUID] = [:]
        for (saved, index) in CheckpointWindow.match(saved: checkpoint.windows, live: live) where stageIDs.contains(checkpoint.windows[saved].stageID) {
            service.windows[index].stageID = checkpoint.windows[saved].stageID
            if let old = checkpoint.windows[saved].id { idMap[old] = service.windows[index].id }
            restored += 1
        }
        restoreLayouts(checkpoint.layouts ?? [], idMap: idMap)
        for (stage, number) in checkpoint.lastFocused where stageIDs.contains(stage) {
            if let window = service.windows.first(where: { $0.windowNumber == number }) { lastFocused[stage] = window.id }
        }
        if stageIDs.contains(checkpoint.activeStageID) { state.activeStageID = checkpoint.activeStageID }
        if restored > 0 { notice = "Restored \(restored) window(s) to their Rooms." }
        windowsChanged()
    }

    /// PRD SET-01: on by default, once. Only for the packaged app; tests and `swift run` are skipped.
    func applyLaunchAtLoginDefault() {
        let key = "didApplyLaunchAtLoginDefault"
        guard Bundle.main.bundlePath.hasSuffix(".app"), ProcessInfo.processInfo.environment["TATAMI_DATA_DIR"] == nil,
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}
