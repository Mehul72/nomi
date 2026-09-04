import SwiftUI

struct ModelSettingsView: View {
    @Environment(ModelManager.self) private var modelManager
    @Environment(Preferences.self) private var preferences
    @State private var removalProblem: String?

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                ForEach(ModelCatalog.languageModels) { model in
                    ModelRow(model: model, isSelected: model.id == modelManager.selectedModel.id) {
                        modelManager.select(model)
                    }
                }
                if let removalProblem {
                    Text(removalProblem).foregroundStyle(.secondary)
                }
            } header: {
                Text("Language model")
            } footer: {
                Text("Models are stored in \(AppDirectories.models.path(percentEncoded: false)). Only the selected model is loaded into memory.")
            }

            Section {
                Toggle("Describe images and layouts on screen", isOn: $preferences.visionModelEnabled)
                if preferences.visionModelEnabled {
                    ModelRow(model: ModelCatalog.visionModel, isSelected: true) {}
                        .environment(modelManager)
                }
            } header: {
                Text("Vision model")
            } footer: {
                Text("Loaded only while answering a question about the screen, then released. With the 14B language model selected, that model is unloaded first and reloaded on the next question.")
            }

            Section("Memory") {
                LabeledContent("State", value: loadStateText)
                if let statistics = modelManager.lastStatistics {
                    LabeledContent("Last generation", value: String(format: "%.1f tokens/s, %d tokens, prompt %.1f s", statistics.tokensPerSecond, statistics.generatedTokens, statistics.promptSeconds))
                }
                HStack {
                    Button("Load now") { Task { _ = await modelManager.loadedLanguageModel() } }
                        .disabled(!modelManager.isSelectedModelInstalled || modelManager.loadState == .loading)
                    Button("Unload") { modelManager.unload() }
                        .disabled(modelManager.languageModel == nil)
                }
            }

            Section {
                LabeledContent("Creativity") {
                    Picker("Creativity", selection: $preferences.generation.temperature) {
                        Text("Precise").tag(Float(0.3))
                        Text("Balanced").tag(Float(0.7))
                        Text("Varied").tag(Float(1.0))
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                LabeledContent("Context window") {
                    Picker("Context window", selection: $preferences.generation.contextTokens) {
                        Text("4K tokens").tag(4096)
                        Text("8K tokens").tag(8192)
                        Text("16K tokens").tag(16384)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                LabeledContent("Longest answer") {
                    Picker("Longest answer", selection: $preferences.generation.maxOutputTokens) {
                        Text("1K tokens").tag(1024)
                        Text("2K tokens").tag(2048)
                        Text("4K tokens").tag(4096)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            } header: {
                Text("Generation")
            } footer: {
                Text("A larger context window remembers more of a conversation and uses more memory. Changes apply to the next conversation.")
            }
        }
        .formStyle(.grouped)
    }

    private var loadStateText: String {
        switch modelManager.loadState {
        case .unloaded: modelManager.isSelectedModelInstalled ? "Not loaded. The first question loads it." : "Not downloaded"
        case .loading: "Loading…"
        case .ready(let seconds): String(format: "Loaded in %.1f s", seconds)
        case .failed(let message): message
        }
    }
}

/// One catalog model: selection, size, download state and the actions that make sense in that state.
struct ModelRow: View {
    @Environment(ModelManager.self) private var modelManager
    let model: ModelDescriptor
    let isSelected: Bool
    let select: () -> Void
    @State private var removalProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: select) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Selected" : "Select \(model.displayName)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                    Text(model.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ModelDownloadControls(model: model)
            }
            if let progress = modelManager.installState(of: model).fractionCompleted {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            if case .interrupted(_, let message?) = modelManager.installState(of: model) {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let result = modelManager.verificationResults[model.id] {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
            if let removalProblem {
                Text(removalProblem).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if case .installed = modelManager.installState(of: model) {
                Button("Verify files") { modelManager.verify(model) }
                Button("Remove from disk") { remove() }
            }
        }
    }

    private func remove() {
        Task {
            do {
                try await modelManager.remove(model)
                removalProblem = nil
            } catch {
                Log.model.error("Removing \(model.id, privacy: .public) failed: \(error, privacy: .public)")
                removalProblem = "The model files could not be removed. Check the folder in Finder."
            }
        }
    }
}

/// Download, cancel, resume and remove, plus the byte counts. Shared by Settings and onboarding.
struct ModelDownloadControls: View {
    @Environment(ModelManager.self) private var modelManager
    let model: ModelDescriptor

    var body: some View {
        HStack(spacing: 8) {
            Text(stateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            switch modelManager.installState(of: model) {
            case .notInstalled:
                Button("Download") { modelManager.download(model) }
            case .downloading:
                Button("Cancel") { modelManager.cancelDownload(model) }
            case .interrupted:
                Button("Resume") { modelManager.download(model) }
            case .installed:
                Button("Remove") { Task { try? await modelManager.remove(model) } }
            }
        }
    }

    private var stateText: String {
        switch modelManager.installState(of: model) {
        case .notInstalled:
            model.approximateSizeText
        case .downloading(let completed, let total):
            "\(Self.bytes(completed)) of \(Self.bytes(total))"
        case .interrupted(let completed, _):
            "Paused at \(Self.bytes(completed))"
        case .installed(let bytes):
            "\(Self.bytes(bytes)) on disk"
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
