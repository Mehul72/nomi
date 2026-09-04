import Foundation

nonisolated enum AgentEvent: Sendable {
    /// A short verb phrase for the status line, such as `Thinking` or `Checking the weather`.
    case status(String)
    case textDelta(String)
    case step(ActivityStep)
    case finished(GenerationStatistics?)
}

nonisolated enum AgentError: LocalizedError {
    case stepLimitReached(Int)

    var errorDescription: String? {
        switch self {
        case .stepLimitReached(let limit):
            "I stopped after \(limit) steps without finishing. Try a smaller request."
        }
    }
}

/// The loop: send the conversation to the model, run the tools it asks for, feed results back, until it answers.
final class Agent: Sendable {
    let executor: ToolExecutor
    let maxIterations: Int

    init(executor: ToolExecutor, maxIterations: Int = 8) {
        self.executor = executor
        self.maxIterations = maxIterations
    }

    /// One user turn. The stream ends with `.finished`, or throws when the model or the step limit fails.
    func respond(
        to userMessage: String,
        session: any LanguageModelSession,
        context: ToolContext,
        transcript: Transcript
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(userMessage: userMessage, session: session, context: context, transcript: transcript, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        userMessage: String,
        session: any LanguageModelSession,
        context: ToolContext,
        transcript: Transcript,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        var outgoing: [ConversationMessage] = [.user(userMessage)]
        await transcript.append(.user(userMessage))
        var statistics: GenerationStatistics?

        for _ in 0..<maxIterations {
            try Task.checkCancellation()
            continuation.yield(.status("Thinking"))
            var filter = HiddenSpanFilter()
            var answer = ""
            var calls: [ModelToolCall] = []

            for try await event in session.send(outgoing) {
                switch event {
                case .text(let delta):
                    let visible = filter.feed(delta)
                    if !visible.isEmpty {
                        answer += visible
                        continuation.yield(.textDelta(visible))
                    }
                case .toolCall(let call):
                    calls.append(call)
                case .finished(let stats):
                    statistics = stats
                }
            }
            let tail = filter.finish()
            if !tail.isEmpty {
                answer += tail
                continuation.yield(.textDelta(tail))
            }
            await transcript.append(.assistant(answer, toolCalls: calls))

            if calls.isEmpty {
                continuation.yield(.finished(statistics))
                return
            }

            outgoing = []
            for call in calls {
                try Task.checkCancellation()
                let label = await executor.registry.tool(named: call.name)?.activityLabel(for: ToolArguments(call.arguments)) ?? "Working"
                continuation.yield(.status(label))
                let outcome = await executor.execute(call, context: context)
                continuation.yield(.step(outcome.step))
                let reply = ConversationMessage.tool(outcome.result.content, callID: call.id)
                outgoing.append(reply)
                await transcript.append(reply)
            }
        }
        throw AgentError.stepLimitReached(maxIterations)
    }
}

/// The conversation as shown in the conversation window, kept apart from the model's own cache.
actor Transcript {
    private(set) var messages: [ConversationMessage] = []

    func append(_ message: ConversationMessage) {
        messages.append(message)
    }
}
