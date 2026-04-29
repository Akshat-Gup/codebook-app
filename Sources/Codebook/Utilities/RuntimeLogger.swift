import Foundation
import os

final class RuntimeLogger: @unchecked Sendable {
    static let shared = RuntimeLogger()

    let isEnabled: Bool
    let logFileURL: URL

    private let logger = Logger(subsystem: "com.codebook.app", category: "runtime")
    private let queue = DispatchQueue(label: "codebook.runtime.logger")
    private let formatter = ISO8601DateFormatter()

    private init() {
        isEnabled = RuntimePolicy.shared.runtimeLoggingEnabled
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let directoryURL = Self.resolveLogDirectory()
        logFileURL = directoryURL.appendingPathComponent("codebook-app.log")
        guard isEnabled else { return }

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: Data())
        }
    }

    func info(_ message: String, metadata: [String: String] = [:]) {
        write(level: "INFO", message: message, metadata: metadata)
    }

    func error(_ message: String, error: Error? = nil, metadata: [String: String] = [:]) {
        var payload = metadata
        if let error {
            payload["error"] = String(describing: error)
        }
        write(level: "ERROR", message: message, metadata: payload)
    }

    private func write(level: String, message: String, metadata: [String: String]) {
        guard isEnabled else { return }
        let sortedMetadata = metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value.replacingOccurrences(of: "\n", with: "\\n"))" }
            .joined(separator: " ")
        let line = "[\(formatter.string(from: Date()))] [\(level)] \(message)\(sortedMetadata.isEmpty ? "" : " \(sortedMetadata)")"

        if level == "ERROR" {
            logger.error("\(line, privacy: .public)")
        } else {
            logger.log("\(line, privacy: .public)")
        }

        let fallbackLogger = logger
        queue.async { [logFileURL] in
            guard let data = (line + "\n").data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: logFileURL)
            else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                fallbackLogger.error("Failed to append runtime log: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func resolveLogDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEBOOK_LOG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let fileManager = FileManager.default
        do {
            let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return appSupport
                .appendingPathComponent("Codebook", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
        } catch {
            // Fall back to Caches or tmp so file logging stays best-effort.
            let fallback = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            return fallback
                .appendingPathComponent("Codebook", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
        }
    }
}
