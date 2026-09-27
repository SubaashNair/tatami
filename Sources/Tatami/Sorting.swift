import AppKit
import SwiftUI
import TatamiCore

struct SortPreview: Identifiable {
    let id = UUID()
    let plan: SortPlan
    /// Index-aligned with `plan.assignments`.
    let windowIDs: [UUID]
}

/// Sort Windows into Stages (M2 decisions 7 and 14), and Cmd+` scoped to the active Stage (STG-07).
extension AppModel {
    func prepareSort() {
        let windows = service.windows.filter { !state.excludedBundleIDs.contains($0.bundleID) }
        guard !windows.isEmpty else { notice = "There are no windows to sort yet."; return }
        let plan = SortPlan.make(bundleIDs: windows.map(\.bundleID), stageNames: state.stages.map(\.name), stageLimit: 9)
        sortPreview = SortPreview(plan: plan, windowIDs: windows.map(\.id))
    }

    /// Offered once, after the first scan that can see windows.
    func offerFirstRunSort() {
        guard isFirstRun, trusted, !service.windows.isEmpty,
              !["TATAMI_ONLY_BUNDLES", "TATAMI_SNAPSHOT_BAR", "TATAMI_SNAPSHOT_TABS"].contains(where: { ProcessInfo.processInfo.environment[$0] != nil })
        else { return }  // integration tests and review snapshots
        isFirstRun = false
        prepareSort()
        showDashboard?()
    }

    func applySort(_ preview: SortPreview) {
        undoSnapshot = snapshot(name: "Before sorting windows")
        for name in preview.plan.create { state.addStage(name: name) }
        for (id, name) in zip(preview.windowIDs, preview.plan.assignments) {
            guard let stage = state.stages.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  let index = service.windows.firstIndex(where: { $0.id == id }) else { continue }
            service.windows[index].stageID = stage.id
        }
        sortPreview = nil
        if managing { reportFailures(applyVisibility(), action: "sort windows") }
        publish(); persist()
        notice = "Sorted \(preview.windowIDs.count) windows into Stages. Undo is available."
    }

    func sortWithAI() {
        sortPreview = nil
        aiPrompt = "Sort my open windows into Stages by project or activity. Keep chat apps together and browsers with the work they belong to."
        showOrganizer?()
    }

    /// Cmd+` among the frontmost app's windows on the active Stage only, skipping parked ones.
    func cycleAppWindows(_ offset: Int) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let candidates = service.windows.filter { $0.pid == pid && $0.stageID == state.activeStageID && $0.hidden == nil && !$0.minimized }
        guard candidates.count > 1 else { return }
        let current = service.focusedID().flatMap { id in candidates.firstIndex { $0.id == id } } ?? 0
        let next = ((current + offset) % candidates.count + candidates.count) % candidates.count
        service.focus(candidates[next].id)
    }
}

struct SortPreviewView: View {
    @ObservedObject var model: AppModel
    let preview: SortPreview

    private var groups: [(stage: String, apps: [String], isNew: Bool)] {
        var order: [String] = [], apps: [String: [String]] = [:]
        for (id, stage) in zip(preview.windowIDs, preview.plan.assignments) {
            if apps[stage] == nil { order.append(stage) }
            let name = model.windows.first { $0.id == id }?.appName ?? "Window"
            apps[stage, default: []].append(name)
        }
        return order.map { stage in
            let counted = Dictionary(grouping: apps[stage]!, by: { $0 }).map { $0.value.count > 1 ? "\($0.key) ×\($0.value.count)" : $0.key }.sorted()
            return (stage, counted, preview.plan.create.contains(stage))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sort your windows into Stages").font(.system(size: 24, weight: .medium, design: .serif))
            Text("Chat and mail go to Comms, browsers to Browse, everything else to Work. Nothing moves until you apply, and Undo puts it back.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(groups, id: \.stage) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(group.stage).font(.system(size: 13, weight: .semibold)); if group.isNew { Text("NEW").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent) } }
                    Text(group.apps.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Not Now") { model.sortPreview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.aiModel != nil { Button("Ask AI Instead…") { model.sortWithAI() } }
                Button("Sort Windows") { model.applySort(preview) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(32).frame(width: 480).foregroundStyle(Theme.ink).tint(Theme.accent)
    }
}
