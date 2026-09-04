import Foundation
import MLXLMCommon
import Synchronization
import Testing
@testable import Nomi

/// In-memory stand-in for the downloader: scripted outcomes, no network, no disk.
final class FakeModelStorage: ModelStorage, @unchecked Sendable {
    enum Outcome: Sendable {
        case succeed(bytes: Int64)
        case fail(String)
        case waitForCancellation
    }

    private struct State {
        var snapshots: [String: ModelDownloader.Snapshot] = [:]
        var bytes: [String: Int64] = [:]
        var outcome: Outcome = .succeed(bytes: 100)
        var downloadCalls = 0
    }

    private let state = Mutex(State())

    var downloadCalls: Int { state.withLock { $0.downloadCalls } }

    func setOutcome(_ outcome: Outcome) {
        state.withLock { $0.outcome = outcome }
    }

    func markInstalled(_ repository: String, bytes: Int64) {
        state.withLock {
            $0.snapshots[repository] = ModelDownloader.Snapshot(repository: repository, revision: "main", files: [], completedAt: .now)
            $0.bytes[repository] = bytes
        }
    }

    nonisolated func snapshot(for repository: String) -> ModelDownloader.Snapshot? {
        state.withLock { $0.snapshots[repository] }
    }

    nonisolated func bytesOnDisk(for repository: String) -> Int64 {
        state.withLock { $0.bytes[repository] ?? 0 }
    }

    func remove(repository: String) async throws {
        state.withLock {
            $0.snapshots[repository] = nil
            $0.bytes[repository] = nil
        }
    }

    func verify(repository: String) async throws -> Bool {
        snapshot(for: repository) != nil
    }

    func download(
        id: String, revision: String?, matching patterns: [String], useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let outcome = state.withLock { state -> Outcome in
            state.downloadCalls += 1
            return state.outcome
        }
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 50
        progressHandler(progress)
        switch outcome {
        case .succeed(let bytes):
            markInstalled(id, bytes: bytes)
            return URL(fileURLWithPath: "/fake/\(id)")
        case .fail(let message):
            state.withLock { $0.bytes[id] = 25 }
            throw NSError(domain: "FakeModelStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        case .waitForCancellation:
            state.withLock { $0.bytes[id] = 25 }
            while true {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }
}

final class FakeLanguageModel: Nomi.LanguageModel {
    let identifier: String
    init(identifier: String) { self.identifier = identifier }
    func makeSession(instructions: String, tools: [ToolSchema], settings: GenerationSettings) -> any LanguageModelSession {
        fatalError("not used")
    }
    func unload() async {}
}

@MainActor
struct ModelManagerTests {
    private func makePreferences() -> Preferences {
        let suite = "ModelManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Preferences(defaults: defaults)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func freshInstallIsNotDownloaded() {
        let manager = ModelManager(preferences: makePreferences(), storage: FakeModelStorage()) { _, _ in FakeLanguageModel(identifier: "x") }
        #expect(manager.installState(of: ModelCatalog.defaultLanguageModel) == .notInstalled)
        #expect(manager.statusLine == .notDownloaded)
        #expect(!manager.isSelectedModelInstalled)
    }

    @Test func downloadReportsProgressThenInstalls() async {
        let storage = FakeModelStorage()
        storage.setOutcome(.succeed(bytes: 4_000))
        let manager = ModelManager(preferences: makePreferences(), storage: storage) { _, _ in FakeLanguageModel(identifier: "x") }
        let model = manager.selectedModel
        manager.download(model)
        #expect(manager.statusLine == .downloading(percent: 0))
        await waitUntil { manager.installState(of: model) == .installed(bytes: 4_000) }
        #expect(manager.installState(of: model) == .installed(bytes: 4_000))
        #expect(manager.statusLine == .installed)
        #expect(manager.isSelectedModelInstalled)
    }

    @Test func cancelledDownloadKeepsPartialBytesForResume() async {
        let storage = FakeModelStorage()
        storage.setOutcome(.waitForCancellation)
        let manager = ModelManager(preferences: makePreferences(), storage: storage) { _, _ in FakeLanguageModel(identifier: "x") }
        let model = manager.selectedModel
        manager.download(model)
        await waitUntil { storage.bytesOnDisk(for: model.id) == 25 }
        manager.cancelDownload(model)
        await waitUntil { manager.installState(of: model) == .interrupted(completed: 25, message: nil) }
        #expect(manager.installState(of: model) == .interrupted(completed: 25, message: nil))

        storage.setOutcome(.succeed(bytes: 100))
        manager.download(model)
        await waitUntil { manager.installState(of: model) == .installed(bytes: 100) }
        #expect(storage.downloadCalls == 2)
    }

    @Test func failedDownloadShowsTheReason() async {
        let storage = FakeModelStorage()
        storage.setOutcome(.fail("The connection dropped."))
        let manager = ModelManager(preferences: makePreferences(), storage: storage) { _, _ in FakeLanguageModel(identifier: "x") }
        let model = manager.selectedModel
        manager.download(model)
        await waitUntil { if case .interrupted = manager.installState(of: model) { return true } else { return false } }
        #expect(manager.installState(of: model) == .interrupted(completed: 25, message: "The connection dropped."))
    }

    @Test func downloadingTwiceStartsOneDownload() async {
        let storage = FakeModelStorage()
        let manager = ModelManager(preferences: makePreferences(), storage: storage) { _, _ in FakeLanguageModel(identifier: "x") }
        let model = manager.selectedModel
        manager.download(model)
        manager.download(model)
        await waitUntil { if case .installed = manager.installState(of: model) { return true } else { return false } }
        #expect(storage.downloadCalls == 1)
    }

    @Test func loadingSharesOneLoadAndRecordsTime() async {
        let storage = FakeModelStorage()
        let model = ModelCatalog.defaultLanguageModel
        storage.markInstalled(model.id, bytes: 1)
        let loads = Mutex(0)
        let manager = ModelManager(preferences: makePreferences(), storage: storage) { descriptor, _ in
            loads.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(20))
            return FakeLanguageModel(identifier: descriptor.id)
        }
        #expect(manager.statusLine == .installed)
        async let first = manager.loadedLanguageModel()
        async let second = manager.loadedLanguageModel()
        let (a, b) = await (first, second)
        #expect(a?.identifier == model.id)
        #expect(b?.identifier == model.id)
        #expect(loads.withLock { $0 } == 1)
        if case .ready(let seconds) = manager.loadState { #expect(seconds >= 0.02) } else { Issue.record("expected ready, got \(manager.loadState)") }
        #expect(manager.statusLine == .ready)
    }

    @Test func loadFailureIsHumanReadable() async {
        let storage = FakeModelStorage()
        storage.markInstalled(ModelCatalog.defaultLanguageModel.id, bytes: 1)
        let manager = ModelManager(preferences: makePreferences(), storage: storage) { _, _ in
            throw NSError(domain: "mlx", code: 7, userInfo: [NSLocalizedDescriptionKey: "safetensors header corrupt"])
        }
        let loaded = await manager.loadedLanguageModel()
        #expect(loaded == nil)
        #expect(manager.loadState == .failed("The local model could not be loaded. Its files may be incomplete. Try downloading it again."))
    }

    @Test func loadWithoutInstallDoesNothing() async {
        let manager = ModelManager(preferences: makePreferences(), storage: FakeModelStorage()) { _, _ in FakeLanguageModel(identifier: "x") }
        #expect(await manager.loadedLanguageModel() == nil)
        #expect(manager.loadState == .unloaded)
    }

    @Test func removingTheLoadedModelUnloadsIt() async throws {
        let storage = FakeModelStorage()
        let model = ModelCatalog.defaultLanguageModel
        storage.markInstalled(model.id, bytes: 1)
        let manager = ModelManager(preferences: makePreferences(), storage: storage) { descriptor, _ in FakeLanguageModel(identifier: descriptor.id) }
        _ = await manager.loadedLanguageModel()
        #expect(manager.languageModel != nil)
        try await manager.remove(model)
        #expect(manager.languageModel == nil)
        #expect(manager.loadState == .unloaded)
        #expect(manager.installState(of: model) == .notInstalled)
    }

    @Test func selectingAnotherModelUnloadsTheCurrentOne() async {
        let storage = FakeModelStorage()
        storage.markInstalled(ModelCatalog.defaultLanguageModel.id, bytes: 1)
        let preferences = makePreferences()
        let manager = ModelManager(preferences: preferences, storage: storage) { descriptor, _ in FakeLanguageModel(identifier: descriptor.id) }
        _ = await manager.loadedLanguageModel()
        manager.select(ModelCatalog.lightweightLanguageModel)
        #expect(manager.languageModel == nil)
        #expect(preferences.selectedModelID == ModelCatalog.lightweightLanguageModel.id)
        #expect(manager.selectedModel == ModelCatalog.lightweightLanguageModel)
        #expect(manager.statusLine == .notDownloaded)
    }
}
