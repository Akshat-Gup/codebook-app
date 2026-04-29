import Foundation

enum SecureFileStore {
    private static let directoryPermissions: NSNumber = 0o700
    private static let filePermissions: NSNumber = 0o600

    static func prepareDirectory(_ directory: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        try? fileManager.setAttributes([.posixPermissions: directoryPermissions], ofItemAtPath: directory.path)
    }

    static func hardenFileIfPresent(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: url.path)
    }

    static func write(_ data: Data, to url: URL) throws {
        prepareDirectory(url.deletingLastPathComponent())
        if let existing = try? Data(contentsOf: url), existing == data { return }
        try data.write(to: url, options: .atomic)
        hardenFileIfPresent(at: url)
    }
}
