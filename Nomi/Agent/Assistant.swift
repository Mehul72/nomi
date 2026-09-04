import AppKit
import Foundation
import Observation

/// The app-level facade the notch talks to: one question at a time, with a visible activity state.
@Observable
final class Assistant {
    enum Activity: Equatable {
        case idle
        case thinking(String)
        case acting(status: String, steps: [ActivityStep])
        case answering(text: String, steps: [ActivityStep])
        case answered(text: String, steps: [ActivityStep])
        case confirming(ConfirmationRequest, steps: [ActivityStep])
        case failed(String, steps: [ActivityStep])

        var isBusy: Bool {
            switch self {
            case .thinking, .acting, .answering, .confirming: true
            case .idle, .answered, .failed: false
            }
        }

        var steps: [ActivityStep] {
            switch self {
            case .idle, .thinking: []
            case .acting(_, let steps), .answering(_, let steps), .answered(_, let steps), .confirming(_, let steps), .failed(_, let steps): steps
            }
        }
    }

    private(set) var activity: Activity = .idle
    private(set) var conversation: [ConversationMessage] = []
    let registry: ToolRegistry
    let transcript = Transcript()

    private let modelManager: ModelManager
    private let preferences: Preferences
    private var agent: Agent!
    private var languageSession: (any LanguageModelSession)?
    private var sessionModelID: String?
    private var currentTask: Task<Void, Never>?
    private var pendingConfirmation: CheckedContinuation<Bool, Never>?
    /// Incremented per question; an older task's late updates are ignored.
    private var generation = 0

    init(modelManager: ModelManager, preferences: Preferences, registry: ToolRegistry) {
        self.modelManager = modelManager
        self.preferences = preferences
        self.registry = registry
        let executor = ToolExecutor(
            registry: registry,
            policy: { [preferences] in
                await MainActor.run { ConfirmationPolicy(confirmsMediumRisk: preferences.confirmsMediumRisk) }
            },
            confirm: { [weak self] request in
                guard let self else { return false }
                return await self.awaitConfirmation(request)
            }
        )
        agent = Agent(executor: executor)
    }

    var isBusy: Bool { activity.isBusy }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        cancel()
        generation += 1
        let generation = generation
        activity = .thinking(modelManager.languageModel == nil ? "Starting local model" : "Thinking")
        currentTask = Task { await self.answer(question, generation: generation) }
    }

    func cancel() {
        pendingConfirmation?.resume(returning: false)
        pendingConfirmation = nil
        currentTask?.cancel()
        currentTask = nil
    }

    /// Clears the visible state after a task ended; a running task keeps going.
    func dismissResult() {
        guard !isBusy else { return }
        activity = .idle
    }

    func startNewConversation() {
        cancel()
        languageSession = nil
        conversation = []
        activity = .idle
    }

    func resolveConfirmation(allow: Bool) {
        pendingConfirmation?.resume(returning: allow)
        pendingConfirmation = nil
    }

    private func awaitConfirmation(_ request: ConfirmationRequest) async -> Bool {
        pendingConfirmation?.resume(returning: false)
        activity = .confirming(request, steps: activity.steps)
        return await withCheckedContinuation { continuation in
            pendingConfirmation = continuation
        }
    }

    /// Applies a state change only while this task is still the current one.
    private func update(_ generation: Int, _ newActivity: Activity) {
        guard generation == self.generation else { return }
        activity = newActivity
    }

    private func answer(_ question: String, generation: Int) async {
        guard let model = await modelManager.loadedLanguageModel() else {
            update(generation, .failed(loadFailureMessage, steps: []))
            return
        }
        if languageSession == nil || sessionModelID != model.identifier {
            languageSession = model.makeSession(instructions: Self.instructions(homeLocation: preferences.homeLocation), tools: registry.schemas, settings: preferences.generation)
            sessionModelID = model.identifier
        }
        guard let session = languageSession else { return }

        let context = ToolContext(isOffline: preferences.offlineMode, homeLocation: preferences.homeLocation)
        var text = ""
        var steps: [ActivityStep] = []
        do {
            for try await event in agent.respond(to: question, session: session, context: context, transcript: transcript) {
                switch event {
                case .status(let status):
                    update(generation, steps.isEmpty ? .thinking(status) : .acting(status: status, steps: steps))
                case .textDelta(let delta):
                    text += delta
                    update(generation, .answering(text: text, steps: steps))
                case .step(let step):
                    steps.append(step)
                    update(generation, .acting(status: "", steps: steps))
                case .finished(let statistics):
                    if let statistics { modelManager.record(statistics) }
                    update(generation, .answered(text: text, steps: steps))
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    if preferences.playsSounds { NSSound(named: "Pop")?.play() }
                }
            }
            // A cancelled consumer ends the stream quietly; keep whatever was already answered.
            if Task.isCancelled {
                update(generation, text.isEmpty ? .idle : .answered(text: text, steps: steps))
            }
        } catch is CancellationError {
            update(generation, text.isEmpty ? .idle : .answered(text: text, steps: steps))
        } catch {
            Log.agent.error("Answering failed: \(error, privacy: .public)")
            update(generation, .failed(Self.humanReadable(error), steps: steps))
        }
        conversation = await transcript.messages
    }

    private var loadFailureMessage: String {
        if case .failed(let message) = modelManager.loadState { return message }
        return "Download the local model in Settings before asking a question."
    }

    private static func humanReadable(_ error: Error) -> String {
        switch error {
        case let agentError as AgentError:
            return agentError.localizedDescription
        case let toolError as ToolError:
            return toolError.localizedDescription
        default:
            return "Something went wrong while answering. Try again."
        }
    }

    static func instructions(homeLocation: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        var lines = [
            "You are Nomi, an assistant that lives in the notch of this Mac.",
            "Answer briefly in plain text. No Markdown headings, tables or code fences unless the user asks for code.",
            "You have tools for the weather, the time, files, the clipboard and the apps on this Mac. Use them instead of saying you cannot; never invent their results. Call one tool at a time and wait for its result.",
            "Today is \(formatter.string(from: Date())) in the \(TimeZone.current.identifier) time zone.",
        ]
        if let homeLocation, !homeLocation.isEmpty {
            lines.append("The user's home location is \(homeLocation).")
        }
        return lines.joined(separator: " ")
    }
}
