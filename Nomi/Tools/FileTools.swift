import Foundation

/// Paths the file tools refuse to touch, whatever the model asks.
nonisolated enum FilePathPolicy {
    static let protectedRelativePaths = [".ssh", ".aws", ".gnupg", "Library/Keychains", "Library/Cookies", ".config/gh"]
    static let protectedAbsolutePrefixes = ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/Library"]

    static func resolve(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let expanded: String
        if path == "~" {
            expanded = home.path(percentEncoded: false)
        } else if path.hasPrefix("~/") {
            expanded = home.appending(path: String(path.dropFirst(2))).path(percentEncoded: false)
        } else {
            expanded = path
        }
        let url = URL(fileURLWithPath: expanded, relativeTo: home).standardizedFileURL
        let string = url.path(percentEncoded: false)
        for prefix in protectedAbsolutePrefixes where string == prefix || string.hasPrefix(prefix + "/") {
            throw ToolError.notPermitted("\(path) is a system location that Nomi does not touch.")
        }
        let homePath = home.path(percentEncoded: false)
        for relative in protectedRelativePaths {
            let protectedPath = homePath.hasSuffix("/") ? homePath + relative : homePath + "/" + relative
            if string == protectedPath || string.hasPrefix(protectedPath + "/") {
                throw ToolError.notPermitted("\(path) holds credentials that Nomi does not read or change.")
            }
        }
        return url
    }
}

struct SearchFilesTool: Tool {
    let name = "search_files"
    let description = "Finds files using the Mac's Spotlight index by words in the file name, optionally limited to a kind (pdf, image, document, spreadsheet, presentation, folder) and to files added or changed within the last N days. Returns up to 20 paths."
    let parameters = [
        ToolParameterSpec.optional("query", .string, "Words that appear in the file name"),
        ToolParameterSpec.optional("kind", .string, "Restrict to a kind of file", allowedValues: ["pdf", "image", "document", "spreadsheet", "presentation", "folder", "any"]),
        ToolParameterSpec.optional("within_days", .integer, "Only files added or modified within this many days"),
        ToolParameterSpec.optional("folder", .string, "Limit the search to this folder, for example ~/Downloads"),
    ]
    let risk = RiskLevel.low
    let symbol = "magnifyingglass"

    func activityLabel(for arguments: ToolArguments) -> String { "Searching your files" }
    func confirmationText(for arguments: ToolArguments) -> String { "Search your files?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let query = try arguments.optionalString("query")?.trimmingCharacters(in: .whitespaces) ?? ""
        let kind = try arguments.optionalString("kind") ?? "any"
        let withinDays = try arguments.optionalInteger("within_days")
        let folder = try arguments.optionalString("folder").map { try FilePathPolicy.resolve($0) }
        guard !query.isEmpty || kind != "any" || withinDays != nil else {
            throw ToolError.invalidArgument(name: "query", reason: "give words to search for, a kind, or a number of days")
        }
        let results = try await SpotlightSearch.run(
            query: query, kind: kind, withinDays: withinDays, folder: folder, limit: 20, timeoutSeconds: 15
        )
        guard !results.isEmpty else {
            return ToolResult(content: "No matching files.", summary: "No files found")
        }
        let listing = results.map { "\($0.path(percentEncoded: false))" }.joined(separator: "\n")
        return ToolResult(content: listing, summary: "Found \(results.count) file\(results.count == 1 ? "" : "s")")
    }
}

struct ReadTextFileTool: Tool {
    let name = "read_text_file"
    let description = "Reads a plain text file (txt, md, csv, json, source code) and returns up to the first 40,000 characters."
    let parameters = [ToolParameterSpec.required("path", .string, "Path to the file, ~ allowed")]
    let risk = RiskLevel.low
    let symbol = "doc.text"

    func activityLabel(for arguments: ToolArguments) -> String {
        "Reading \(Self.displayName(arguments))"
    }

    func confirmationText(for arguments: ToolArguments) -> String {
        "Read \(Self.displayName(arguments))?"
    }

    private static func displayName(_ arguments: ToolArguments) -> String {
        ((try? arguments.string("path")) as NSString?)?.lastPathComponent ?? "the file"
    }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let url = try FilePathPolicy.resolve(try arguments.string("path"))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ToolError.failed("There is no file at \(url.path(percentEncoded: false)).")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 20_000_000 else { throw ToolError.failed("The file is larger than 20 MB.") }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ToolError.failed("The file is not plain text.")
        }
        let limit = 40_000
        let clipped = text.count > limit ? String(text.prefix(limit)) + "\n[truncated at \(limit) characters]" : text
        return ToolResult(content: clipped, summary: "Read \(url.lastPathComponent)")
    }
}

struct CreateTextFileTool: Tool {
    let name = "create_text_file"
    let description = "Creates a new plain text file with the given content. Fails if the file already exists unless overwrite is true."
    let parameters = [
        ToolParameterSpec.required("path", .string, "Where to create the file, ~ allowed"),
        ToolParameterSpec.required("content", .string, "The text to write"),
        ToolParameterSpec.optional("overwrite", .boolean, "Replace an existing file"),
    ]
    let risk = RiskLevel.medium
    let symbol = "doc.badge.plus"

    func activityLabel(for arguments: ToolArguments) -> String { "Creating a file" }

    func confirmationText(for arguments: ToolArguments) -> String {
        let path = (try? arguments.string("path")) ?? "a file"
        let count = (try? arguments.string("content"))?.count ?? 0
        let overwrite = (try? arguments.bool("overwrite", default: false)) ?? false
        return "\(overwrite ? "Replace" : "Create") \(path) with \(count) characters of text?"
    }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let url = try FilePathPolicy.resolve(try arguments.string("path"))
        let content = try arguments.string("content")
        let overwrite = try arguments.bool("overwrite", default: false)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), !overwrite {
            throw ToolError.failed("\(url.lastPathComponent) already exists. Ask for overwrite to replace it.")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return ToolResult(content: "Wrote \(content.count) characters to \(url.path(percentEncoded: false)).", summary: "Created \(url.lastPathComponent)")
    }
}

struct MoveFileTool: Tool {
    let name = "move_file"
    let description = "Moves or renames a file or folder. The destination can be a folder or a full new path. Nothing is ever deleted."
    let parameters = [
        ToolParameterSpec.required("source", .string, "Current path"),
        ToolParameterSpec.required("destination", .string, "Target folder or full target path"),
    ]
    let risk = RiskLevel.medium
    let symbol = "folder"

    func activityLabel(for arguments: ToolArguments) -> String { "Moving a file" }

    func confirmationText(for arguments: ToolArguments) -> String {
        let source = ((try? arguments.string("source")) as NSString?)?.lastPathComponent ?? "the file"
        let destination = (try? arguments.string("destination")) ?? "the destination"
        return "Move \(source) to \(destination)?"
    }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let source = try FilePathPolicy.resolve(try arguments.string("source"))
        var destination = try FilePathPolicy.resolve(try arguments.string("destination"))
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw ToolError.failed("There is nothing at \(source.path(percentEncoded: false)).")
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false), isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw ToolError.failed("\(destination.lastPathComponent) already exists.") }
            destination = destination.appending(path: source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                throw ToolError.failed("\(destination.lastPathComponent) already exists in that folder.")
            }
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
        return ToolResult(content: "Moved to \(destination.path(percentEncoded: false)).", summary: "Moved \(source.lastPathComponent)")
    }
}

/// A Spotlight metadata query wrapped in async/await with a time limit.
enum SpotlightSearch {
    nonisolated struct Query: Sendable {
        var words: [String]
        var kind: String
        var since: Date?
        var folder: URL?
        var limit: Int
    }

    static func run(query: String, kind: String, withinDays: Int?, folder: URL?, limit: Int, timeoutSeconds: Int) async throws -> [URL] {
        let since = withinDays.map { Calendar.current.date(byAdding: .day, value: -max($0, 0), to: .now) ?? .now }
        let spec = Query(words: query.split(separator: " ").map(String.init), kind: kind, since: since, folder: folder, limit: limit)
        return try await withThrowingTaskGroup(of: [URL].self) { group in
            group.addTask { await MetadataQueryRunner.results(for: spec) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw ToolError.timedOut(seconds: timeoutSeconds)
            }
            let first = try await group.next() ?? []
            group.cancelAll()
            return first
        }
    }
}

/// NSMetadataQuery needs a run loop and notifications; this keeps that on the main actor behind one await.
@MainActor
private final class MetadataQueryRunner: NSObject {
    private let query = NSMetadataQuery()
    private var continuation: CheckedContinuation<[URL], Never>?
    private let limit: Int

    private init(limit: Int) {
        self.limit = limit
    }

    static func results(for spec: SpotlightSearch.Query) async -> [URL] {
        let runner = MetadataQueryRunner(limit: spec.limit)
        return await runner.run(spec)
    }

    private func run(_ spec: SpotlightSearch.Query) async -> [URL] {
        var predicates = spec.words.map { NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", $0) }
        if let kindPredicate = Self.kindPredicate(spec.kind) {
            predicates.append(kindPredicate)
        }
        if let since = spec.since {
            predicates.append(NSPredicate(format: "kMDItemContentModificationDate >= %@ OR kMDItemDateAdded >= %@", since as NSDate, since as NSDate))
        }
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        query.searchScopes = [spec.folder ?? NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemContentModificationDateKey, ascending: false)]
        NotificationCenter.default.addObserver(self, selector: #selector(finished), name: .NSMetadataQueryDidFinishGathering, object: query)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if !query.start() {
                continuation.resume(returning: [])
                self.continuation = nil
            }
        }
    }

    @objc private func finished() {
        query.disableUpdates()
        let urls = (0..<min(query.resultCount, limit)).compactMap { index -> URL? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
        query.stop()
        NotificationCenter.default.removeObserver(self)
        continuation?.resume(returning: urls)
        continuation = nil
    }

    private static func kindPredicate(_ kind: String) -> NSPredicate? {
        switch kind {
        case "pdf": NSPredicate(format: "kMDItemContentTypeTree == %@", "com.adobe.pdf")
        case "image": NSPredicate(format: "kMDItemContentTypeTree == %@", "public.image")
        case "document": NSPredicate(format: "kMDItemContentTypeTree == %@ OR kMDItemContentTypeTree == %@", "public.text", "org.openxmlformats.wordprocessingml.document")
        case "spreadsheet": NSPredicate(format: "kMDItemContentTypeTree == %@ OR kMDItemContentTypeTree == %@", "public.spreadsheet", "org.openxmlformats.spreadsheetml.sheet")
        case "presentation": NSPredicate(format: "kMDItemContentTypeTree == %@ OR kMDItemContentTypeTree == %@", "public.presentation", "org.openxmlformats.presentationml.presentation")
        case "folder": NSPredicate(format: "kMDItemContentType == %@", "public.folder")
        default: nil
        }
    }
}
