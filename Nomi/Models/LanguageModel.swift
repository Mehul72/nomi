import Foundation

/// One turn of a conversation as the model sees it.
nonisolated struct ConversationMessage: Sendable, Equatable {
    enum Role: String, Sendable {
        case system, user, assistant, tool
    }

    var role: Role
    var content: String
    /// Set on assistant messages that requested tools, and on tool messages answering a request.
    var toolCalls: [ModelToolCall] = []
    var toolCallID: String?

    static func user(_ content: String) -> Self { Self(role: .user, content: content) }
    static func assistant(_ content: String, toolCalls: [ModelToolCall] = []) -> Self {
        Self(role: .assistant, content: content, toolCalls: toolCalls)
    }
    static func tool(_ content: String, callID: String?) -> Self {
        Self(role: .tool, content: content, toolCallID: callID)
    }
}

/// A tool invocation the model asked for, with arguments already parsed as JSON values.
nonisolated struct ModelToolCall: Sendable, Equatable, Hashable {
    var id: String
    var name: String
    var arguments: [String: JSONValue]
}

/// Timing gathered after a generation, used for the performance numbers in the README.
nonisolated struct GenerationStatistics: Sendable, Equatable {
    var promptTokens: Int
    var generatedTokens: Int
    var promptSeconds: Double
    var generationSeconds: Double
    var stoppedByLimit: Bool

    var tokensPerSecond: Double {
        generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0
    }
}

nonisolated enum LanguageModelEvent: Sendable {
    case text(String)
    case toolCall(ModelToolCall)
    case finished(GenerationStatistics)
}

/// The JSON schema of a tool as sent to the model, in the OpenAI function-calling shape.
typealias ToolSchema = [String: any Sendable]

/// Generation controls exposed in Settings. Defaults follow the Qwen3 recommendations for non-thinking mode.
nonisolated struct GenerationSettings: Codable, Equatable, Sendable {
    var temperature: Float = 0.7
    var topP: Float = 0.8
    var maxOutputTokens: Int = 2048
    /// Cap on the KV cache so a long conversation cannot exhaust unified memory.
    var contextTokens: Int = 8192
}

/// A loaded local language model. Sessions keep their own KV cache so multi-step tool loops do not re-read the transcript.
protocol LanguageModel: AnyObject, Sendable {
    var identifier: String { get }

    func makeSession(instructions: String, tools: [ToolSchema], settings: GenerationSettings) -> any LanguageModelSession

    /// Releases GPU memory held by caches. Callers drop their references to the model first.
    func unload() async
}

/// A conversation with a model. Use from one task at a time.
protocol LanguageModelSession: AnyObject, Sendable {
    /// Appends messages and streams the model's reply. Cancelling the consuming task stops generation.
    func send(_ messages: [ConversationMessage]) -> AsyncThrowingStream<LanguageModelEvent, Error>
}
