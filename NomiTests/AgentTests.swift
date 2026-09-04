import Foundation
import Synchronization
import Testing
@testable import Nomi

/// A scripted model: each `send` pops the next reply. Records what it was sent.
final class ScriptedSession: LanguageModelSession, @unchecked Sendable {
    enum Reply: Sendable {
        case text([String])
        case toolCall(name: String, arguments: [String: JSONValue], text: String = "")
    }

    private let replies: Mutex<[Reply]>
    let received = Mutex<[[ConversationMessage]]>([])

    init(_ replies: [Reply]) {
        self.replies = Mutex(replies)
    }

    func send(_ messages: [ConversationMessage]) -> AsyncThrowingStream<LanguageModelEvent, Error> {
        received.withLock { $0.append(messages) }
        let reply = replies.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        return AsyncThrowingStream { continuation in
            switch reply {
            case .text(let chunks):
                chunks.forEach { continuation.yield(.text($0)) }
            case .toolCall(let name, let arguments, let text):
                if !text.isEmpty { continuation.yield(.text(text)) }
                continuation.yield(.toolCall(ModelToolCall(id: "call-\(name)", name: name, arguments: arguments)))
            case nil:
                continuation.yield(.text("(no script)"))
            }
            continuation.yield(.finished(GenerationStatistics(promptTokens: 1, generatedTokens: 1, promptSeconds: 0, generationSeconds: 0.1, stoppedByLimit: false)))
            continuation.finish()
        }
    }
}

struct AddTool: Tool {
    let name = "add"
    let description = "Adds"
    let parameters = [ToolParameterSpec.required("a", .integer, "a"), ToolParameterSpec.required("b", .integer, "b")]
    let risk: RiskLevel
    let symbol = "plus"
    func activityLabel(for arguments: ToolArguments) -> String { "Adding" }
    func confirmationText(for arguments: ToolArguments) -> String { "Add the numbers?" }
    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let sum = try arguments.integer("a") + arguments.integer("b")
        return ToolResult(content: "\(sum)", summary: "Added to \(sum)")
    }
}

struct AgentTests {
    private func makeAgent(risk: RiskLevel = .low, confirm: Bool = true, maxIterations: Int = 8) -> Agent {
        let registry = ToolRegistry(tools: [AddTool(risk: risk)])
        let executor = ToolExecutor(registry: registry, policy: { ConfirmationPolicy() }, confirm: { _ in confirm })
        return Agent(executor: executor, maxIterations: maxIterations)
    }

    private func collect(_ agent: Agent, session: ScriptedSession, question: String = "q") async throws -> (text: String, steps: [ActivityStep], statuses: [String], finished: Bool) {
        var text = ""
        var steps: [ActivityStep] = []
        var statuses: [String] = []
        var finished = false
        let transcript = Transcript()
        for try await event in agent.respond(to: question, session: session, context: ToolContext(isOffline: false, homeLocation: nil), transcript: transcript) {
            switch event {
            case .textDelta(let delta): text += delta
            case .step(let step): steps.append(step)
            case .status(let status): statuses.append(status)
            case .finished: finished = true
            }
        }
        return (text, steps, statuses, finished)
    }

    @Test func plainAnswerFinishesWithoutTools() async throws {
        let session = ScriptedSession([.text(["Hel", "lo"])])
        let result = try await collect(makeAgent(), session: session)
        #expect(result.text == "Hello")
        #expect(result.finished)
        #expect(result.steps.isEmpty)
        #expect(session.received.withLock { $0 } == [[.user("q")]])
    }

    @Test func toolCallIsExecutedAndItsResultSentBack() async throws {
        let session = ScriptedSession([
            .toolCall(name: "add", arguments: ["a": .number(2), "b": .number(3)]),
            .text(["The sum is 5."]),
        ])
        let result = try await collect(makeAgent(), session: session)
        #expect(result.text == "The sum is 5.")
        #expect(result.steps.map(\.text) == ["Added to 5"])
        #expect(result.statuses == ["Thinking", "Adding", "Thinking"])
        let second = session.received.withLock { $0 }[1]
        #expect(second == [.tool("5", callID: "call-add")])
    }

    @Test func unknownToolIsReportedToTheModelNotCrashed() async throws {
        let session = ScriptedSession([
            .toolCall(name: "launch_rockets", arguments: [:]),
            .text(["I cannot do that."]),
        ])
        let result = try await collect(makeAgent(), session: session)
        #expect(result.text == "I cannot do that.")
        #expect(result.steps.first?.isError == true)
        let second = session.received.withLock { $0 }[1]
        #expect(second.first?.content.contains("no tool called launch_rockets") == true)
    }

    @Test func malformedArgumentsAreReportedToTheModel() async throws {
        let session = ScriptedSession([
            .toolCall(name: "add", arguments: ["a": .string("two")]),
            .text(["Sorry."]),
        ])
        let result = try await collect(makeAgent(), session: session)
        let second = session.received.withLock { $0 }[1]
        #expect(second.first?.content.contains("The argument a is invalid: expected a whole number") == true)
        #expect(result.steps.first?.isError == true)
    }

    @Test func loopStopsAtTheIterationLimit() async {
        let endless = Array(repeating: ScriptedSession.Reply.toolCall(name: "add", arguments: ["a": .number(1), "b": .number(1)]), count: 20)
        let session = ScriptedSession(endless)
        await #expect(throws: AgentError.self) {
            _ = try await collect(makeAgent(maxIterations: 3), session: session)
        }
        #expect(session.received.withLock { $0.count } == 3)
    }

    @Test func deniedConfirmationTellsTheModel() async throws {
        let session = ScriptedSession([
            .toolCall(name: "add", arguments: ["a": .number(1), "b": .number(1)]),
            .text(["Understood."]),
        ])
        let result = try await collect(makeAgent(risk: .high, confirm: false), session: session)
        #expect(result.steps.first?.text.hasPrefix("Not allowed") == true)
        let second = session.received.withLock { $0 }[1]
        #expect(second.first?.content.contains("did not allow") == true)
    }

    @Test func hiddenReasoningNeverReachesTheUser() async throws {
        let session = ScriptedSession([.text(["<think>", "plan", "</think>", "Visible"])])
        let result = try await collect(makeAgent(), session: session)
        #expect(result.text == "Visible")
    }

    @Test func cancellationStopsTheLoop() async throws {
        let endless = Array(repeating: ScriptedSession.Reply.toolCall(name: "add", arguments: ["a": .number(1), "b": .number(1)]), count: 50)
        let session = ScriptedSession(endless)
        let agent = makeAgent(maxIterations: 50)
        let task = Task {
            var count = 0
            for try await event in agent.respond(to: "q", session: session, context: ToolContext(isOffline: false, homeLocation: nil), transcript: Transcript()) {
                if case .step = event { count += 1 }
                if count == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return count
        }
        let steps = try await task.value
        #expect(steps == 2)
        let sentWhenStopped = session.received.withLock { $0.count }
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.received.withLock { $0.count } == sentWhenStopped)
        #expect(sentWhenStopped < 50)
    }
}
