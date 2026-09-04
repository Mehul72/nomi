import CoreGraphics
import CoreImage
import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

/// A local model that can look at an image. Loaded for one question and released afterwards.
protocol VisionModel: AnyObject, Sendable {
    var identifier: String { get }
    func describe(_ image: CGImage, question: String) async throws -> String
    func unload() async
}

final class MLXVisionModel: VisionModel {
    let identifier: String
    private let container: ModelContainer

    private init(identifier: String, container: ModelContainer) {
        self.identifier = identifier
        self.container = container
    }

    static func load(descriptor: ModelDescriptor, downloader: any Downloader) async throws -> MLXVisionModel {
        let container = try await VLMModelFactory.shared.loadContainer(
            from: downloader,
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: descriptor.id)
        )
        return MLXVisionModel(identifier: descriptor.id, container: container)
    }

    func describe(_ image: CGImage, question: String) async throws -> String {
        // Around a megapixel keeps screen text legible without flooding the context with image tokens.
        let session = ChatSession(
            container,
            instructions: "You describe what is visible in a screenshot of a Mac window. Be concrete and brief: name the app, the content, any charts, images, errors or dialogs, and the key text.",
            generateParameters: GenerateParameters(maxTokens: 600, temperature: 0.2),
            processing: UserInput.Processing(resize: nil, minPixels: 256 * 28 * 28, maxPixels: 1280 * 28 * 28)
        )
        return try await session.respond(to: question, image: .ciImage(CIImage(cgImage: image)))
    }

    func unload() async {
        Memory.clearCache()
    }
}
