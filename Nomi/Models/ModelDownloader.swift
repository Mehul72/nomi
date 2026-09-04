import CryptoKit
import Foundation
import MLXLMCommon

/// What the model manager needs from the place models are stored, so tests can substitute a fake.
protocol ModelStorage: Downloader {
    nonisolated func snapshot(for repository: String) -> ModelDownloader.Snapshot?
    nonisolated func bytesOnDisk(for repository: String) -> Int64
    func remove(repository: String) async throws
    func verify(repository: String) async throws -> Bool
}

/// Downloads model repositories from the Hugging Face hub into Application Support.
///
/// Files are written next to a `.partial` suffix and renamed when complete, so an interrupted download
/// resumes from where it stopped. A marker file records that a snapshot is complete, which also lets
/// a finished model load while offline.
actor ModelDownloader: ModelStorage {
    nonisolated struct RemoteFile: Codable, Sendable, Equatable {
        let path: String
        let size: Int64
        /// SHA-256 of the content for large files stored through Git LFS.
        let sha256: String?
    }

    nonisolated struct Snapshot: Codable, Sendable {
        let repository: String
        let revision: String
        let files: [RemoteFile]
        let completedAt: Date
    }

    enum DownloadError: LocalizedError {
        case badResponse(String, Int)
        case sizeMismatch(String, expected: Int64, actual: Int64)
        case checksumMismatch(String)
        case offline(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let path, let status):
                "The download of \(path) failed (HTTP \(status))."
            case .sizeMismatch(let path, let expected, let actual):
                "\(path) is \(actual) bytes but should be \(expected). Its download will restart."
            case .checksumMismatch(let path):
                "\(path) does not match the published checksum."
            case .offline(let repository):
                "\(repository) is not downloaded and the file list could not be fetched. Check the connection and try again."
            }
        }
    }

    nonisolated static let markerFileName = "nomi-snapshot.json"
    nonisolated private static let hubBase = URL(string: "https://huggingface.co")!

    let modelsDirectory: URL
    private let session: URLSession
    /// Progress callbacks are throttled to this many bytes so the UI is not flooded.
    private let progressGranularity: Int64 = 4 * 1024 * 1024

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    nonisolated func directory(for repository: String) -> URL {
        modelsDirectory.appending(path: repository, directoryHint: .isDirectory)
    }

    nonisolated func snapshot(for repository: String) -> Snapshot? {
        let url = directory(for: repository).appending(path: Self.markerFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Bytes present on disk for a repository, complete or partial.
    nonisolated func bytesOnDisk(for repository: String) -> Int64 {
        let root = directory(for: repository)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func remove(repository: String) throws {
        let root = directory(for: repository)
        if FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
    }

    // MARK: Downloader

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let revision = revision ?? "main"
        let root = directory(for: id)
        if !useLatest, let snapshot = snapshot(for: id), snapshot.revision == revision {
            let progress = Progress(totalUnitCount: snapshot.files.reduce(0) { $0 + $1.size })
            progress.completedUnitCount = progress.totalUnitCount
            progressHandler(progress)
            return root
        }

        let files: [RemoteFile]
        do {
            files = try await listFiles(repository: id, revision: revision).filter { file in
                patterns.contains { pattern in fnmatch(pattern, file.path, 0) == 0 }
            }
        } catch {
            Log.model.error("File listing for \(id, privacy: .public) failed: \(error, privacy: .public)")
            throw DownloadError.offline(id)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let progress = Progress(totalUnitCount: files.reduce(0) { $0 + $1.size })
        progress.completedUnitCount = files.reduce(0) { $0 + (isComplete($1, in: root) ? $1.size : 0) }
        progressHandler(progress)

        for file in files where !isComplete(file, in: root) {
            try Task.checkCancellation()
            try await download(file, repository: id, revision: revision, into: root, progress: progress, progressHandler: progressHandler)
        }

        let snapshot = Snapshot(repository: id, revision: revision, files: files, completedAt: .now)
        try JSONEncoder().encode(snapshot).write(to: root.appending(path: Self.markerFileName), options: .atomic)
        return root
    }

    /// Recomputes the checksum of every large file. Slow for multi-gigabyte models, so only run on request.
    func verify(repository: String) async throws -> Bool {
        guard let snapshot = snapshot(for: repository) else { return false }
        let root = directory(for: repository)
        for file in snapshot.files {
            try Task.checkCancellation()
            let url = root.appending(path: file.path)
            guard isComplete(file, in: root) else { return false }
            if let expected = file.sha256 {
                let actual = try await Self.sha256(of: url)
                if actual != expected {
                    Log.model.error("Checksum mismatch for \(file.path, privacy: .public)")
                    return false
                }
            }
        }
        return true
    }

    // MARK: Hub requests

    private struct TreeEntry: Decodable {
        struct LFS: Decodable {
            let oid: String
            let size: Int64
        }
        let type: String
        let path: String
        let size: Int64?
        let lfs: LFS?
    }

    private func listFiles(repository: String, revision: String) async throws -> [RemoteFile] {
        var components = URLComponents(url: Self.hubBase.appending(path: "api/models/\(repository)/tree/\(revision)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.badResponse(repository, (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode([TreeEntry].self, from: data)
            .filter { $0.type == "file" }
            .map { RemoteFile(path: $0.path, size: $0.lfs?.size ?? $0.size ?? 0, sha256: $0.lfs?.oid) }
    }

    private func isComplete(_ file: RemoteFile, in root: URL) -> Bool {
        let url = root.appending(path: file.path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return Int64(size) == file.size
    }

    private func download(
        _ file: RemoteFile,
        repository: String,
        revision: String,
        into root: URL,
        progress: Progress,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws {
        let destination = root.appending(path: file.path)
        let partial = root.appending(path: file.path + ".partial")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)

        var resumeOffset = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if resumeOffset > file.size {
            try FileManager.default.removeItem(at: partial)
            resumeOffset = 0
        }
        if resumeOffset == file.size {
            try FileManager.default.moveItem(at: partial, to: destination)
            return
        }

        var request = URLRequest(url: Self.hubBase.appending(path: "\(repository)/resolve/\(revision)/\(file.path)"))
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.badResponse(file.path, -1) }
        switch http.statusCode {
        case 206:
            break
        case 200:
            // The server ignored the range, so whatever was downloaded before is stale.
            try? FileManager.default.removeItem(at: partial)
            resumeOffset = 0
        default:
            throw DownloadError.badResponse(file.path, http.statusCode)
        }

        if !FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) {
            FileManager.default.createFile(atPath: partial.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var written = resumeOffset
        var sinceReport: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        progress.completedUnitCount += resumeOffset
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                sinceReport += Int64(buffer.count)
                progress.completedUnitCount += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if sinceReport >= progressGranularity {
                    sinceReport = 0
                    progressHandler(progress)
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            progress.completedUnitCount += Int64(buffer.count)
        }
        try handle.close()
        progressHandler(progress)

        guard written == file.size else {
            try? FileManager.default.removeItem(at: partial)
            throw DownloadError.sizeMismatch(file.path, expected: file.size, actual: written)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    private static func sha256(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            try Task.checkCancellation()
            await Task.yield()
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
