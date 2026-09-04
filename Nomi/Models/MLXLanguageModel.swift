import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs a Qwen model through MLX. Tool calls are parsed by MLXLMCommon in the model's own format.
final class MLXLanguageModel: LanguageModel {
    let identifier: String
    private let container: ModelContainer

    init(identifier: String, container: ModelContainer) {
        self.identifier = identifier
        self.container = container
    }

    static func load(
        descriptor: ModelDescriptor,
        downloader: any Downloader,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> MLXLanguageModel {
        let configuration = ModelConfiguration(id: descriptor.id)
        let container = try await LLMModelFactory.shared.loadContainer(
            from: downloader,
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration,
            progressHandler: progressHandler
        )
        return MLXLanguageModel(identifier: descriptor.id, container: container)
    }

    func makeSession(instructions: String, tools: [ToolSchema], settings: GenerationSettings) -> any LanguageModelSession {
        MLXChatSession(container: container, instructions: instructions, tools: tools, settings: settings)
    }

    func unload() async {
        Memory.clearCache()
    }
}

/// Wraps `ChatSession`, which is not thread-safe; the agent drives one session from one task at a time.
final class MLXChatSession: LanguageModelSession, @unchecked Sendable {
    private let session: ChatSession

    init(container: ModelContainer, instructions: String, tools: [ToolSchema], settings: GenerationSettings) {
        session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(
                maxTokens: settings.maxOutputTokens,
                maxKVSize: settings.contextTokens,
                temperature: settings.temperature,
                topP: settings.topP
            ),
            // Hidden reasoning is never shown, so it is not generated either.
            additionalContext: ["enable_thinking": false],
            tools: tools.isEmpty ? nil : tools
        )
    }

    func send(_ messages: [ConversationMessage]) -> AsyncThrowingStream<LanguageModelEvent, Error> {
        let upstream = session.streamDetails(to: messages.map(Self.chatMessage))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await generation in upstream {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(.text(text))
                        case .toolCall(let call):
                            continuation.yield(.toolCall(Self.modelToolCall(call)))
                        case .info(let info):
                            continuation.yield(.finished(GenerationStatistics(
                                promptTokens: info.promptTokenCount,
                                generatedTokens: info.generationTokenCount,
                                promptSeconds: info.promptTime,
                                generationSeconds: info.generateTime,
                                stoppedByLimit: info.stopReason == .length
                            )))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func chatMessage(_ message: ConversationMessage) -> Chat.Message {
        switch message.role {
        case .system:
            .system(message.content)
        case .user:
            .user(message.content)
        case .assistant:
            .assistant(message.content, toolCalls: message.toolCalls.isEmpty ? nil : message.toolCalls.map(toolCall))
        case .tool:
            .tool(message.content, id: message.toolCallID)
        }
    }

    private static func toolCall(_ call: ModelToolCall) -> ToolCall {
        ToolCall(
            function: .init(name: call.name, arguments: call.arguments.mapValues(mlxValue)),
            id: call.id
        )
    }

    private static func modelToolCall(_ call: ToolCall) -> ModelToolCall {
        ModelToolCall(
            id: call.id ?? UUID().uuidString,
            name: call.function.name,
            arguments: call.function.arguments.mapValues(jsonValue)
        )
    }

    private static func jsonValue(_ value: MLXLMCommon.JSONValue) -> Nomi.JSONValue {
        switch value {
        case .null: .null
        case .bool(let bool): .bool(bool)
        case .int(let int): .number(Double(int))
        case .double(let double): .number(double)
        case .string(let string): .string(string)
        case .array(let array): .array(array.map(jsonValue))
        case .object(let object): .object(object.mapValues(jsonValue))
        }
    }

    private static func mlxValue(_ value: Nomi.JSONValue) -> MLXLMCommon.JSONValue {
        switch value {
        case .null: .null
        case .bool(let bool): .bool(bool)
        case .number(let number):
            if number == number.rounded(), abs(number) < 1e15 { .int(Int(number)) } else { .double(number) }
        case .string(let string): .string(string)
        case .array(let array): .array(array.map(mlxValue))
        case .object(let object): .object(object.mapValues(mlxValue))
        }
    }
}
