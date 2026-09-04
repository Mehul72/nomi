import Foundation

/// Where the app keeps everything it creates. Nothing here is ever inside the repository.
nonisolated enum AppDirectories {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Nomi", directoryHint: .isDirectory)
    }
}
