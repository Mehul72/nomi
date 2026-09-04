import Foundation
import Observation

/// Owns which models are on disk and which one is loaded. One large language model is resident at a time.
@Observable
final class ModelManager {
    enum InstallState: Equatable {
        case notInstalled
        case downloading(completed: Int64, total: Int64)
        /// Some bytes are on disk; the next download resumes from them.
        case interrupted(completed: Int64, message: String?)
        case installed(bytes: Int64)

        var fractionCompleted: Double? {
            if case .downloading(let completed, let total) = self, total > 0 {
                return Double(completed) / Double(total)
            }
            return nil
        }
    }

    enum LoadState: Equatable {
        case unloaded
        case loading
        case ready(loadSeconds: Double)
        case failed(String)
    }

    private(set) var installStates: [String: InstallState] = [:]
    private(set) var loadState: LoadState = .unloaded
    private(set) var languageModel: (any LanguageModel)?
    private(set) var lastStatistics: GenerationStatistics?
    private(set) var verificationResults: [String: String] = [:]

    typealias Loader = @Sendable (ModelDescriptor, any ModelStorage) async throws -> any LanguageModel

    let storage: any ModelStorage
    private let loader: Loader
    private let preferences: Preferences
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var loadTask: Task<(any LanguageModel)?, Never>?
    private var verifyTasks: [String: Task<Void, Never>] = [:]

    init(
        preferences: Preferences,
        storage: any ModelStorage = ModelDownloader(modelsDirectory: AppDirectories.models),
        loader: @escaping Loader = { descriptor, storage in
            try await MLXLanguageModel.load(descriptor: descriptor, downloader: storage) { _ in }
        }
    ) {
        self.preferences = preferences
        self.storage = storage
        self.loader = loader
        refreshInstallStates()
    }

    var selectedModel: ModelDescriptor {
        ModelCatalog.descriptor(for: preferences.selectedModelID) ?? ModelCatalog.defaultLanguageModel
    }

    func select(_ model: ModelDescriptor) {
        guard model.id != preferences.selectedModelID else { return }
        preferences.selectedModelID = model.id
        unload()
    }

    func installState(of model: ModelDescriptor) -> InstallState {
        installStates[model.id] ?? .notInstalled
    }

    var isSelectedModelInstalled: Bool {
        if case .installed = installState(of: selectedModel) { return true }
        return false
    }

    /// The one-line status the notch shows under the input field.
    var statusLine: ModelStatusLine {
        switch loadState {
        case .ready: return .ready
        case .loading: return .starting
        case .failed: return .notDownloaded
        case .unloaded: break
        }
        switch installState(of: selectedModel) {
        case .installed: return .installed
        case .downloading(let completed, let total):
            return .downloading(percent: total > 0 ? Int(Double(completed) / Double(total) * 100) : 0)
        case .interrupted, .notInstalled: return .notDownloaded
        }
    }

    func refreshInstallStates() {
        for model in ModelCatalog.languageModels {
            if case .downloading = installStates[model.id] { continue }
            installStates[model.id] = Self.diskState(of: model, storage: storage)
        }
    }

    private static func diskState(of model: ModelDescriptor, storage: any ModelStorage) -> InstallState {
        let bytes = storage.bytesOnDisk(for: model.id)
        if storage.snapshot(for: model.id) != nil {
            return .installed(bytes: bytes)
        }
        return bytes > 0 ? .interrupted(completed: bytes, message: nil) : .notInstalled
    }

    // MARK: Download

    private static let filePatterns = ["*.safetensors", "*.json", "*.jinja"]

    func download(_ model: ModelDescriptor) {
        guard downloadTasks[model.id] == nil else { return }
        installStates[model.id] = .downloading(completed: storage.bytesOnDisk(for: model.id), total: model.approximateBytes)
        let storage = self.storage
        let onProgress: @Sendable (Progress) -> Void = { [weak self] progress in
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            Task { @MainActor in self?.downloadProgressed(model, completed: completed, total: total) }
        }
        downloadTasks[model.id] = Task { [weak self] in
            let outcome: InstallState
            do {
                _ = try await storage.download(
                    id: model.id, revision: nil, matching: Self.filePatterns, useLatest: false, progressHandler: onProgress
                )
                outcome = .installed(bytes: storage.bytesOnDisk(for: model.id))
            } catch is CancellationError {
                outcome = .interrupted(completed: storage.bytesOnDisk(for: model.id), message: nil)
            } catch {
                Log.model.error("Download of \(model.id, privacy: .public) failed: \(error, privacy: .public)")
                outcome = .interrupted(completed: storage.bytesOnDisk(for: model.id), message: error.localizedDescription)
            }
            self?.downloadFinished(model, outcome: outcome)
        }
    }

    private func downloadProgressed(_ model: ModelDescriptor, completed: Int64, total: Int64) {
        guard case .downloading = installStates[model.id] else { return }
        installStates[model.id] = .downloading(completed: completed, total: total)
    }

    private func downloadFinished(_ model: ModelDescriptor, outcome: InstallState) {
        installStates[model.id] = outcome
        downloadTasks[model.id] = nil
    }

    func cancelDownload(_ model: ModelDescriptor) {
        downloadTasks[model.id]?.cancel()
    }

    func remove(_ model: ModelDescriptor) async throws {
        cancelDownload(model)
        if languageModel?.identifier == model.id {
            unload()
        }
        try await storage.remove(repository: model.id)
        verificationResults[model.id] = nil
        installStates[model.id] = .notInstalled
    }

    func verify(_ model: ModelDescriptor) {
        guard verifyTasks[model.id] == nil else { return }
        verificationResults[model.id] = "Checking…"
        let storage = self.storage
        verifyTasks[model.id] = Task { [weak self] in
            let result: String
            do {
                result = try await storage.verify(repository: model.id)
                    ? "All files match their checksums."
                    : "A file is damaged. Remove the model and download it again."
            } catch {
                result = "Verification stopped: \(error.localizedDescription)"
            }
            Log.model.notice("Verification of \(model.id, privacy: .public): \(result, privacy: .public)")
            self?.verificationResults[model.id] = result
            self?.verifyTasks[model.id] = nil
        }
    }

    // MARK: Load

    /// Loads the selected model if needed and returns it. Concurrent callers share one load.
    func loadedLanguageModel() async -> (any LanguageModel)? {
        if let languageModel { return languageModel }
        if let loadTask { return await loadTask.value }
        guard isSelectedModelInstalled else { return nil }
        let model = selectedModel
        let storage = self.storage
        let loader = self.loader
        loadState = .loading
        let task = Task<(any LanguageModel)?, Never> { [weak self] in
            let started = Date()
            do {
                let loaded = try await loader(model, storage)
                let seconds = Date().timeIntervalSince(started)
                Log.model.notice("Loaded \(model.id, privacy: .public) in \(seconds, format: .fixed(precision: 2)) s")
                self?.languageModel = loaded
                self?.loadState = .ready(loadSeconds: seconds)
                self?.loadTask = nil
                return loaded
            } catch {
                Log.model.error("Loading \(model.id, privacy: .public) failed: \(error, privacy: .public)")
                self?.loadState = .failed("The local model could not be loaded. Its files may be incomplete. Try downloading it again.")
                self?.loadTask = nil
                return nil
            }
        }
        loadTask = task
        return await task.value
    }

    func unload() {
        loadTask?.cancel()
        loadTask = nil
        let model = languageModel
        languageModel = nil
        loadState = .unloaded
        Task { await model?.unload() }
    }

    func record(_ statistics: GenerationStatistics) {
        lastStatistics = statistics
    }
}
