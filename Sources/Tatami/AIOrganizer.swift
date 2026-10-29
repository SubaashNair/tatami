import Foundation
import TatamiCore

enum AIState {
    case idle, needsDisclosure, working
    case ready(ValidatedPlan)
    case failed(String)
}

private let maxPlanWindows = 150

extension AppModel {
    var aiConfig: AIConfig { state.ai ?? AIConfig() }
    var aiPreset: AIPreset { AIPreset.find(aiConfig.presetID) }
    var aiSendsTitles: Bool { aiConfig.sendTitles[aiPreset.id] ?? true }
    var aiModel: String? {
        let chosen = aiConfig.models[aiPreset.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return chosen.isEmpty ? aiPreset.defaultModel : chosen
    }

    func updateAI(_ change: (inout AIConfig) -> Void) {
        var config = aiConfig
        change(&config)
        state.ai = config
        persist()
    }

    func planContext() -> (PlanContext, [String: UUID]) {
        let eligible = service.windows.filter { !state.excludedBundleIDs.contains($0.bundleID) }.prefix(maxPlanWindows)
        var refs: [String: UUID] = [:]
        let windows = eligible.enumerated().map { index, window -> PlanWindow in
            let ref = "w\(index + 1)"
            refs[ref] = window.id
            let display = service.display(for: window.realFrame).flatMap { d in service.displays.firstIndex { $0.id == d.id } } ?? 0
            return PlanWindow(ref: ref, appName: window.appName, bundleID: window.bundleID, title: window.title,
                              stageName: state.stages.first { $0.id == window.stageID }?.name ?? state.activeStage.name,
                              display: display + 1, frame: window.realFrame)
        }
        return (PlanContext(windows: windows, stageNames: state.stages.map(\.name), displays: service.displays.map(\.area.size)), refs)
    }

    /// While a plan is on screen, asking again refines it (decision 2).
    func organize(acknowledgeDisclosure: Bool = false) {
        let request = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let preset = aiPreset, config = aiConfig
        // Consent is for a destination: a custom endpoint is a different destination whenever its host changes.
        let consent = preset.id == "custom" ? "custom:\(URL(string: config.customBaseURL)?.host ?? config.customBaseURL)" : preset.id
        if !preset.isLocal(config) && !config.disclosed.contains(consent) {
            guard acknowledgeDisclosure else { aiState = .needsDisclosure; return }
            updateAI { if $0.disclosed.count >= 20 { $0.disclosed.removeFirst() }; $0.disclosed.append(consent) }
        }
        guard let model = aiModel else { aiState = .failed(AIError.missingModel.localizedDescription); return }
        let (context, refs) = planContext()  // events keep the window list current
        guard !context.windows.isEmpty else {
            aiState = .failed(trusted ? "There are no windows to arrange." : "Connect Accessibility so Tatami can see your windows.")
            return
        }
        var previous: String?
        if case .ready(let plan) = aiState { previous = plan.summary }
        let user = AIPrompt.user(request: request, context: context, includeTitles: aiSendsTitles, previousSummary: previous)
        let key = KeychainStore.read(preset.id)

        aiTask?.cancel()
        aiState = .working
        aiTask = Task { [weak self] in
            do {
                let plan = try await Self.requestPlan(preset: preset, config: config, model: model, key: key, user: user)
                guard let self, !Task.isCancelled else { return }
                self.aiRefs = refs
                self.aiState = .ready(plan.validate(against: context))
            } catch {
                // A superseded request must not overwrite the newer one's state; cancelOrganize already reset it.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self?.aiState = .failed(error.localizedDescription)
            }
        }
    }

    /// One retry that tells the model why its reply could not be read (decision 3).
    private static func requestPlan(preset: AIPreset, config: AIConfig, model: String, key: String?, user: String) async throws -> AIPlan {
        let reply = try await AIClient.complete(preset: preset, config: config, model: model, key: key, system: AIPrompt.system, user: user)
        do { return try AIPlan.parse(reply) } catch {
            try Task.checkCancellation()
            let retry = user + "\n\nYour previous reply could not be read (\(error.localizedDescription)). Reply with only the JSON object."
            return try AIPlan.parse(try await AIClient.complete(preset: preset, config: config, model: model, key: key, system: AIPrompt.system, user: retry))
        }
    }

    func cancelOrganize() { aiTask?.cancel(); aiTask = nil; aiState = .idle }
    func discardPlan() { aiState = .idle }

    /// One transaction: snapshot for Undo, Stage changes and assignments, visibility, then placement.
    func applyPlan(_ plan: ValidatedPlan) {
        guard !plan.valid.isEmpty else { return }
        undoSnapshot = snapshot(name: "Before AI arrangement")
        var skipped = 0, failures = 0
        func stageID(_ name: String) -> UUID? { state.stages.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id }
        func windowIndex(_ ref: String) -> Int? { aiRefs[ref].flatMap { id in service.windows.firstIndex { $0.id == id } } }

        for action in plan.valid {
            switch action {
            case .createStage(let name):
                if state.addStage(name: name) == nil { failures += 1 }
            case .renameStage(let from, let to):
                if let i = state.stages.firstIndex(where: { $0.name == from }) { state.stages[i].name = to } else { failures += 1 }
            case .assign(let ref, let stage):
                guard let i = windowIndex(ref) else { skipped += 1; continue }
                if let id = stageID(stage) { service.windows[i].stageID = id } else { failures += 1 }
            case .snap: continue
            }
        }
        // Unminimize before moving: AX cannot reliably resize minimized windows.
        if managing { failures += applyVisibility() }
        for case .snap(let ref, let zone, let display) in plan.valid {
            guard let i = windowIndex(ref) else { skipped += 1; continue }
            let window = service.windows[i]
            // A window assigned to another Stage is parked: judge its display by its real frame, and record the snap
            // with place() so it appears there when that Stage is shown, instead of pulling it onto this desk.
            let current = window.hidden == nil ? window.frame : window.realFrame
            let target = display.flatMap { service.displays.indices.contains($0 - 1) ? service.displays[$0 - 1] : nil } ?? service.display(for: current)
            guard let target, service.place(window.id, at: zone.frame(in: target.area, gap: state.gap)) else { failures += 1; continue }
        }

        aiState = .idle
        aiPrompt = ""
        publish(); persist()
        notice = "Arrangement applied. Undo is available." + (skipped > 0 ? " \(skipped) closed window(s) were skipped." : "")
        reportFailures(failures, action: "apply the AI arrangement")
        hideOrganizer?()
    }

    func describe(_ action: PlanAction) -> String {
        func window(_ ref: String) -> String {
            guard let id = aiRefs[ref], let w = windows.first(where: { $0.id == id }) else { return "a closed window" }
            return w.title.isEmpty ? w.appName : "\(w.appName): \(w.title.prefix(40))"
        }
        switch action {
        case .createStage(let name): return "Create Stage “\(name)”"
        case .renameStage(let from, let to): return "Rename “\(from)” to “\(to)”"
        case .assign(let ref, let stage): return "Move \(window(ref)) to \(stage)"
        case .snap(let ref, let zone, let display): return "Place \(window(ref)): \(zone.label.lowercased())" + (display.map { " on display \($0)" } ?? "")
        }
    }

    func saveKey(_ key: String) {
        do {
            try KeychainStore.save(key, account: aiPreset.id)
            notice = key.isEmpty ? "\(aiPreset.name) key removed." : "\(aiPreset.name) key saved to your Keychain."
            if !key.isEmpty { loadModels() }
        } catch { self.error = error.localizedDescription }
    }

    /// Test Connection: lists models, which authenticates without spending tokens.
    func loadModels() {
        let preset = aiPreset, config = aiConfig, key = KeychainStore.read(preset.id)
        Task { [weak self] in
            do {
                let list = try await AIClient.models(preset: preset, config: config, key: key)
                guard let self, self.aiPreset.id == preset.id else { return }  // provider changed while waiting
                self.aiModels = list
                self.notice = "Connected to \(preset.name). \(list.count) models available."
            } catch { self?.error = error.localizedDescription }
        }
    }
}
