import Foundation

struct CLIInstaller {
    let environment: [String: String]
    let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    @discardableResult
    func installBundledCLIIfNeeded(bundleURL: URL, logger: RuntimeLogger? = nil) throws -> URL? {
        let helperURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("codebook-cli", isDirectory: false)

        guard fileManager.isExecutableFile(atPath: helperURL.path) else {
            logger?.info("Skipped CLI install", metadata: ["reason": "missing-helper"])
            return nil
        }

        let installDirectory = preferredInstallDirectory()
        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let installURL = installDirectory.appendingPathComponent("codebook", isDirectory: false)
        try replaceInstallCopy(at: installURL, source: helperURL)
        try ensurePathEntry(for: installDirectory)

        logger?.info("Installed CLI launcher", metadata: ["path": installURL.path])
        return installURL
    }

    private func preferredInstallDirectory() -> URL {
        if let explicitHome = environment["HOME"], !explicitHome.isEmpty {
            return URL(fileURLWithPath: explicitHome, isDirectory: true)
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private func replaceInstallCopy(at installURL: URL, source: URL) throws {
        let installPath = installURL.path

        if fileManager.fileExists(atPath: installPath) || (try? fileManager.destinationOfSymbolicLink(atPath: installPath)) != nil {
            try? fileManager.removeItem(at: installURL)
        }

        try fileManager.removeItemIfExists(at: installURL)
        try fileManager.copyItem(at: source, to: installURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
    }

    private func ensurePathEntry(for directory: URL) throws {
        let directoryPath = directory.path
        let currentPath = environment["PATH"] ?? ""
        if currentPath.split(separator: ":").contains(where: { String($0) == directoryPath }) {
            return
        }

        let profileURL = preferredProfileURL()
        if !fileManager.fileExists(atPath: profileURL.path) {
            fileManager.createFile(atPath: profileURL.path, contents: Data())
        }

        let exportLine = "export PATH=\"\(directoryPath):$PATH\""
        let existing = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
        guard !existing.contains(exportLine) else { return }

        let prefix = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let updated = existing + prefix + exportLine + "\n"
        try updated.write(to: profileURL, atomically: true, encoding: .utf8)
    }

    private func preferredProfileURL() -> URL {
        if let explicitHome = environment["HOME"], !explicitHome.isEmpty {
            return URL(fileURLWithPath: explicitHome, isDirectory: true).appendingPathComponent(".zprofile")
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zprofile")
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) || (try? destinationOfSymbolicLink(atPath: url.path)) != nil {
            try? removeItem(at: url)
        }
    }
}
