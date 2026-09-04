import Foundation

/// A completed step for the activity timeline.
nonisolated struct ActivityStep: Sendable, Identifiable, Equatable {
    let id: UUID
    let symbol: String
    let text: String
    let isError: Bool

    init(symbol: String, text: String, isError: Bool = false) {
        id = UUID()
        self.symbol = symbol
        self.text = text
        self.isError = isError
    }
}

/// Validates a tool call, applies the confirmation policy, runs the tool with a time limit, and reports the outcome.
final class ToolExecutor: Sendable {
    typealias Confirm = @Sendable (ConfirmationRequest) async -> Bool

    let registry: ToolRegistry
    private let policy: @Sendable () async -> ConfirmationPolicy
    private let confirm: Confirm
    private let timeoutSeconds: Int

    init(registry: ToolRegistry, timeoutSeconds: Int = 60, policy: @escaping @Sendable () async -> ConfirmationPolicy, confirm: @escaping Confirm) {
        self.registry = registry
        self.timeoutSeconds = timeoutSeconds
        self.policy = policy
        self.confirm = confirm
    }

    struct Outcome: Sendable {
        var result: ToolResult
        var step: ActivityStep
        var wasDenied = false
    }

    func execute(_ call: ModelToolCall, context: ToolContext) async -> Outcome {
        Log.agent.info("Tool call \(call.name, privacy: .public) with arguments \(call.arguments.keys.sorted().joined(separator: ","), privacy: .public)")
        let outcome = await run(call, context: context)
        Log.agent.info("Tool \(call.name, privacy: .public) finished, error=\(outcome.result.isError), denied=\(outcome.wasDenied)")
        return outcome
    }

    private func run(_ call: ModelToolCall, context: ToolContext) async -> Outcome {
        guard let tool = await registry.tool(named: call.name) else {
            let message = ToolError.unknownTool(call.name).localizedDescription
            return Outcome(result: .failure(message), step: ActivityStep(symbol: "questionmark.circle", text: message, isError: true))
        }

        let arguments: ToolArguments
        do {
            arguments = try tool.validate(call.arguments)
        } catch {
            let message = error.localizedDescription
            Log.agent.notice("Rejected call to \(call.name, privacy: .public): \(message, privacy: .public)")
            return Outcome(result: .failure(message), step: ActivityStep(symbol: tool.symbol, text: "\(tool.name) was given bad arguments", isError: true))
        }

        if await policy().requiresConfirmation(for: tool.risk) {
            let request = ConfirmationRequest(id: UUID(), text: tool.confirmationText(for: arguments), risk: tool.risk)
            guard await confirm(request) else {
                let message = "The user did not allow this action."
                return Outcome(
                    result: .failure(message),
                    step: ActivityStep(symbol: "hand.raised", text: "Not allowed: \(tool.activityLabel(for: arguments).lowercased())", isError: true),
                    wasDenied: true
                )
            }
        }

        do {
            let result = try await withTimeout(seconds: timeoutSeconds) {
                try await tool.execute(arguments, context: context)
            }
            return Outcome(result: result, step: ActivityStep(symbol: tool.symbol, text: result.summary, isError: result.isError))
        } catch is CancellationError {
            return Outcome(result: .failure("Cancelled."), step: ActivityStep(symbol: "xmark.circle", text: "Stopped", isError: true))
        } catch {
            let message = error.localizedDescription
            Log.agent.error("Tool \(call.name, privacy: .public) failed: \(message, privacy: .public)")
            return Outcome(result: .failure(message), step: ActivityStep(symbol: tool.symbol, text: message, isError: true))
        }
    }

    private func withTimeout<T: Sendable>(seconds: Int, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ToolError.timedOut(seconds: seconds)
            }
            guard let first = try await group.next() else { throw ToolError.timedOut(seconds: seconds) }
            group.cancelAll()
            return first
        }
    }
}
