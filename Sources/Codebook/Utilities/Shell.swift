import Foundation

struct ShellResult {
    let stdout: String
    let status: Int32
}

enum Shell {
    @discardableResult
    static func run(
        _ launchPath: String = "/usr/bin/env",
        arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codebook-shell-\(UUID().uuidString)", isDirectory: true)
        let stdoutURL = tempDirectory.appendingPathComponent("stdout.log")
        let stderrURL = tempDirectory.appendingPathComponent("stderr.log")
        SecureFileStore.prepareDirectory(tempDirectory)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        SecureFileStore.hardenFileIfPresent(at: stdoutURL)
        SecureFileStore.hardenFileIfPresent(at: stderrURL)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        if let timeout {
            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }
            try process.run()

            let deadline = DispatchTime.now() + timeout
            if semaphore.wait(timeout: deadline) == .timedOut {
                process.terminate()
                process.waitUntilExit()
                try stdoutHandle.close()
                try stderrHandle.close()
                let partial = (try? String(decoding: Data(contentsOf: stdoutURL), as: UTF8.self)) ?? ""
                return ShellResult(stdout: partial, status: -1)
            }
        } else {
            try process.run()
            process.waitUntilExit()
        }

        try stdoutHandle.close()
        try stderrHandle.close()

        let stdout = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
        return ShellResult(stdout: stdout, status: process.terminationStatus)
    }
}
