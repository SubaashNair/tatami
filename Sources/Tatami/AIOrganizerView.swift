import SwiftUI
import TatamiCore

/// Shared by the floating panel (Control+Option+Z) and the dashboard's AI Organizer section.
struct AIOrganizerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let preset = model.aiPreset
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("Arrange with AI").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(preset.name) · \(model.aiModel ?? "no model")").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            TextField("Describe your desk, e.g. “Xcode and Simulator on a Build Room, Slack on the side screen”", text: $model.aiPrompt, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder).font(.system(size: 13))
                .onSubmit { model.organize() }
                .disabled(isWorking)
            content(preset)
        }
        .foregroundStyle(Theme.ink).tint(Theme.accent)
    }

    private var isWorking: Bool { if case .working = model.aiState { return true }; return false }

    @ViewBuilder private func content(_ preset: AIPreset) -> some View {
        switch model.aiState {
        case .idle:
            HStack {
                Text(dataLine(preset)).font(.system(size: 10)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Organize") { model.organize() }.buttonStyle(.borderedProminent)
                    .disabled(model.aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        case .needsDisclosure:
            disclosure(preset)
        case .working:
            HStack {
                ProgressView().controlSize(.small)
                Text("Asking \(preset.name)…").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Cancel") { model.cancelOrganize() }.keyboardShortcut(.cancelAction)
            }
        case .ready(let plan):
            preview(plan)
        case .failed(let message):
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Try Again") { model.organize() }
            }
        }
    }

    private func dataLine(_ preset: AIPreset) -> String {
        let config = model.aiConfig
        if preset.isLocal(config) { return "Runs on this Mac (\(preset.host(config)))." }
        return "Sends app names\(model.aiSendsTitles ? ", window titles" : ""), Room names, and window positions to \(preset.host(config))."
    }

    private func disclosure(_ preset: AIPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Before sending to \(preset.host(model.aiConfig))").font(.system(size: 12, weight: .semibold))
            Text("Tatami sends each window's app name, bundle ID, position, and Room, plus your Room names and display sizes. Window titles can contain document names, email subjects, or client names. No screenshots, file contents, or keystrokes are sent. The request goes directly from this Mac to \(preset.name) using your key.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Toggle("Include window titles", isOn: titlesBinding(model)).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
            HStack {
                Button("Cancel") { model.discardPlan() }
                Spacer()
                Button("Continue") { model.organize(acknowledgeDisclosure: true) }.buttonStyle(.borderedProminent)
            }
        }.padding(14).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func preview(_ plan: ValidatedPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !plan.summary.isEmpty { Text(plan.summary).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(plan.valid.enumerated()), id: \.offset) { _, action in
                        Label(model.describe(action), systemImage: "checkmark.circle").foregroundStyle(Theme.ink)
                    }
                    ForEach(Array(plan.dropped.enumerated()), id: \.offset) { _, dropped in
                        Label("\(dropped.description): \(dropped.reason)", systemImage: "xmark.circle").foregroundStyle(.orange)
                    }
                }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 220)
            if plan.valid.isEmpty { Text("Nothing in this plan can be applied. Edit your request and ask again.").font(.system(size: 11)).foregroundStyle(Theme.muted) }
            else if !model.managing { Text("Rooms take effect when you start managing.").font(.system(size: 10)).foregroundStyle(Theme.muted) }
            HStack {
                Button("Discard") { model.discardPlan() }
                Spacer()
                Button("Ask Again") { model.organize() }.help("Refine this plan with your edited request")
                Button("Apply") { model.applyPlan(plan) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(plan.valid.isEmpty)
            }
        }
    }
}

@MainActor private func titlesBinding(_ model: AppModel) -> Binding<Bool> {
    Binding(get: { model.aiSendsTitles }, set: { value in let id = model.aiPreset.id; model.updateAI { $0.sendTitles[id] = value } })
}

/// Preferences → AI. Keys go to the Keychain through `saveKey`; nothing secret is bound to persisted state.
struct AISettingsBox: View {
    @ObservedObject var model: AppModel
    @State private var keyDraft = ""
    @State private var urlDraft = ""
    @State private var hasKey = false

    var body: some View {
        let preset = model.aiPreset
        VStack(alignment: .leading, spacing: 18) {
            Text("AI ORGANIZER").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted)
            Group {
                Picker("Provider", selection: Binding(get: { model.aiConfig.presetID }, set: { id in model.updateAI { $0.presetID = id }; model.aiModels = [] })) {
                    ForEach(AIPreset.all) { Text($0.name).tag($0.id) }
                }
                if preset.id == "custom" {
                    HStack {
                        TextField("Base URL, e.g. https://example.com/v1", text: $urlDraft).textFieldStyle(.roundedBorder)
                        Button("Save") {
                            guard AIConfig.acceptableBaseURL(urlDraft) else { model.error = AIError.badEndpoint.localizedDescription; return }
                            model.updateAI { $0.customBaseURL = urlDraft }
                        }.disabled(urlDraft == model.aiConfig.customBaseURL)
                    }
                }
                if !preset.isLocal {
                    HStack {
                        SecureField(hasKey ? "Key saved in Keychain. Enter a new one to replace it." : "API key", text: $keyDraft).textFieldStyle(.roundedBorder)
                        // Spaces alone would save as empty, which deletes the saved key; only Remove does that.
                        Button("Save") { model.saveKey(keyDraft); keyDraft = ""; refreshKey() }.disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if hasKey { Button("Remove") { model.saveKey(""); refreshKey() } }
                    }
                }
                HStack {
                    TextField(preset.defaultModel ?? "Model", text: Binding(get: { model.aiConfig.models[preset.id] ?? "" }, set: { value in model.updateAI { $0.models[preset.id] = String(value.prefix(200)) } }))
                        .textFieldStyle(.roundedBorder)
                    if !model.aiModels.isEmpty {
                        Menu("Choose") { ForEach(model.aiModels, id: \.self) { name in Button(name) { model.updateAI { $0.models[preset.id] = name } } } }.frame(width: 90)
                    }
                    Button("Test Connection") { model.loadModels() }
                }
                Toggle("Send window titles to \(preset.name)", isOn: titlesBinding(model))
                Text("Keys are stored in your Keychain and never included in exports. Requests go directly from this Mac to the provider. Open the organizer with Control + Option + Z while managing, or from the menu bar.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 12))
        }
        .padding(24).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .task(id: preset.id) { refreshKey(); urlDraft = model.aiConfig.customBaseURL }
    }

    private func refreshKey() { hasKey = KeychainStore.read(model.aiPreset.id) != nil }
}
