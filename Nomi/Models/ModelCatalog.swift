import Foundation

/// A model the app knows how to download and run. The identifier is the Hugging Face repository.
nonisolated struct ModelDescriptor: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case language
        case vision
        case embedding
    }

    let id: String
    let displayName: String
    let kind: Kind
    /// Approximate size of the files that get downloaded, for the download prompt. The real total comes from the hub.
    let approximateBytes: Int64
    let summary: String

    var approximateSizeText: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }
}

/// The fixed set of models this build supports.
nonisolated enum ModelCatalog {
    /// Qwen3 14B stays the default: no newer Qwen release exists in the same size class on the MLX registry.
    static let defaultLanguageModel = ModelDescriptor(
        id: "mlx-community/Qwen3-14B-4bit",
        displayName: "Qwen3 14B",
        kind: .language,
        approximateBytes: 8_320_000_000,
        summary: "The default. Strongest answers and tool use on this machine, about 8.3 GB."
    )

    static let lightweightLanguageModel = ModelDescriptor(
        id: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
        displayName: "Qwen3 4B",
        kind: .language,
        approximateBytes: 2_280_000_000,
        summary: "Lightweight option. Faster and smaller, about 2.3 GB, with simpler answers."
    )

    static let languageModels = [defaultLanguageModel, lightweightLanguageModel]

    /// Optional: only downloaded when the user turns on screen descriptions in Settings.
    static let visionModel = ModelDescriptor(
        id: "mlx-community/Qwen3-VL-4B-Instruct-4bit",
        displayName: "Qwen3 VL 4B",
        kind: .vision,
        approximateBytes: 3_110_000_000,
        summary: "Describes images, charts and layouts on screen. Loaded only for a screen question."
    )

    static var all: [ModelDescriptor] { languageModels + [visionModel] }

    static func descriptor(for id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }
}
