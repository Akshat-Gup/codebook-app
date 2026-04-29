import AppKit
import Foundation

struct PromptWorkspaceActionService {
    enum ActionError: LocalizedError {
        case unsupportedOpenThread(IntegrationProvider)
        case unsupportedFork(IntegrationProvider)
        case missingApplication(IntegrationProvider)
        case missingCLI(IntegrationProvider)
        case missingCodebookCLI
        case missingSourcePath
        case missingResumableThread(IntegrationProvider)
        case terminalLaunchFailed(String)
        case automationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedOpenThread(let provider):
                return "Open Thread is not available for \(provider.title) yet."
            case .unsupportedFork(let provider):
                return "Fork is not available for \(provider.title) yet."
            case .missingApplication(let provider):
                return "\(provider.title) is not installed on this Mac."
            case .missingCLI(let provider):
                return "\(provider.title) CLI is not installed, so Codebook cannot resume that thread yet."
            case .missingCodebookCLI:
                return "Codebook CLI is not installed, so Open Thread cannot launch the exact resume command yet."
            case .missingSourcePath:
                return "This prompt does not have a thread source to open."
            case .missingResumableThread(let provider):
                return "This \(provider.title) prompt does not include a resumable thread ID."
            case .terminalLaunchFailed(let message):
                return message
            case .automationFailed(let message):
                return message
            }
        }
    }

    func threadPrompts(for prompt: ImportedPrompt, in allPrompts: [ImportedPrompt]) -> [ImportedPrompt] {
        if let sourceContextID = normalizedContextID(prompt.sourceContextID) {
            let matches = allPrompts.filter { candidate in
                candidate.provider == prompt.provider &&
                candidate.projectKey == prompt.projectKey &&
                normalizedContextID(candidate.sourceContextID) == sourceContextID
            }
            if !matches.isEmpty {
                return sortPrompts(matches)
            }
        }

        let matches = allPrompts.filter { candidate in
            candidate.provider == prompt.provider &&
            candidate.projectKey == prompt.projectKey &&
            candidate.sourcePath == prompt.sourcePath
        }
        return matches.isEmpty ? [prompt] : sortPrompts(matches)
    }

    func canOpenThread(for prompt: ImportedPrompt) -> Bool {
        guard let plan = threadResumePlan(for: prompt),
              codebookCLIInvocation() != nil
        else {
            return false
        }
        return canLaunchThreadPlan(plan, for: prompt.provider)
    }

    func openThread(for prompt: ImportedPrompt) throws {
        guard let plan = threadResumePlan(for: prompt) else {
            throw unsupportedOpenThreadError(for: prompt)
        }
        guard let codebookInvocation = codebookCLIInvocation() else {
            throw ActionError.missingCodebookCLI
        }

        if plan.interactive {
            guard let providerCommand = providerCommandName(for: prompt.provider),
                  commandExists(named: providerCommand) else {
                throw ActionError.missingCLI(prompt.provider)
            }
            let command = terminalResumeCommand(codebookInvocation: codebookInvocation, arguments: plan.arguments)
            try launchInTerminal(command)
        } else {
            try launchCodebookCommand(codebookInvocation + plan.arguments)
        }
    }

    func availableForkTargets() -> [IntegrationProvider] {
        IntegrationProvider.allCases.filter { canForkToProvider($0) }
    }

    private func canForkToProvider(_ provider: IntegrationProvider) -> Bool {
        switch provider {
        case .codex, .cursor, .opencode, .antigravity:
            return applicationURL(for: provider) != nil
        case .claude:
            return commandExists(named: "claude")
        case .copilot:
            return commandExists(named: "code") || appExists(named: "Visual Studio Code") || appExists(named: "VSCodium")
        }
    }

    func canFork(to provider: IntegrationProvider) -> Bool {
        canForkToProvider(provider)
    }

    func fork(prompts: [ImportedPrompt], to provider: IntegrationProvider, projectPath: String?) throws {
        guard canFork(to: provider) else {
            throw ActionError.unsupportedFork(provider)
        }

        let text = promptPayload(from: prompts)
        guard !text.isEmpty else { return }

        switch provider {
        case .cursor:
            guard let url = cursorPromptURL(text: text, projectPath: projectPath) else {
                throw ActionError.unsupportedFork(.cursor)
            }
            NSWorkspace.shared.open(url)
        case .codex, .opencode:
            try automateNewThread(in: provider, text: text)
        case .claude:
            try forkToClaude(text: text, projectPath: projectPath)
        case .copilot:
            try forkToCopilot(text: text, projectPath: projectPath)
        case .antigravity:
            try automateNewThread(in: provider, text: text)
        }
    }

    func cursorPromptURL(text: String, projectPath: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "cursor"
        components.host = "anysphere.cursor-deeplink"
        components.path = "/prompt"

        var queryItems = [URLQueryItem(name: "text", value: text)]
        if let projectPath, !projectPath.isEmpty {
            queryItems.append(URLQueryItem(name: "workspace", value: projectPath))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func promptPayload(from prompts: [ImportedPrompt]) -> String {
        sortPrompts(prompts)
            .map(\.body)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n---\n\n")
    }

    private func sortPrompts(_ prompts: [ImportedPrompt]) -> [ImportedPrompt] {
        prompts.sorted { lhs, rhs in
            if lhs.capturedAt == rhs.capturedAt {
                return lhs.id < rhs.id
            }
            return lhs.capturedAt < rhs.capturedAt
        }
    }

    private func normalizedContextID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func applicationURL(for provider: IntegrationProvider) -> URL? {
        let workspace = NSWorkspace.shared
        if let bundleID = bundleIdentifier(for: provider),
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }

        if let appName = applicationName(for: provider) {
            let appURL = URL(fileURLWithPath: "/Applications/\(appName).app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                return appURL
            }
        }

        return nil
    }

    private func bundleIdentifier(for provider: IntegrationProvider) -> String? {
        switch provider {
        case .codex:
            return "com.openai.codex"
        case .cursor:
            return "com.todesktop.230313mzl4w4u92"
        case .opencode:
            return "ai.opencode.desktop"
        case .copilot:
            return "com.microsoft.VSCode"
        case .antigravity:
            return "com.antigravity.app"
        case .claude:
            return nil
        }
    }

    private func applicationName(for provider: IntegrationProvider) -> String? {
        switch provider {
        case .codex:
            return "Codex"
        case .cursor:
            return "Cursor"
        case .opencode:
            return "OpenCode"
        case .copilot:
            return "Visual Studio Code"
        case .antigravity:
            return "Antigravity"
        case .claude:
            return nil
        }
    }

    private func unsupportedOpenThreadError(for prompt: ImportedPrompt) -> ActionError {
        switch prompt.provider {
        case .codex, .claude, .opencode:
            return .missingResumableThread(prompt.provider)
        case .cursor, .copilot, .antigravity:
            return .unsupportedOpenThread(prompt.provider)
        }
    }

    private func threadResumePlan(for prompt: ImportedPrompt) -> ThreadResumePlan? {
        let sourcePath = prompt.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourcePath.isEmpty, FileManager.default.fileExists(atPath: sourcePath) else {
            return nil
        }
        let projectPath = normalizedContextID(prompt.projectPath) ?? normalizedContextID(prompt.gitRoot)
        switch prompt.provider {
        case .codex:
            guard codexSessionID(for: prompt) != nil else { return nil }
            var arguments = [
                "open-thread",
                "--provider", prompt.provider.rawValue,
                "--source-path", sourcePath
            ]
            if let contextID = normalizedContextID(prompt.sourceContextID) {
                arguments.append(contentsOf: ["--context-id", contextID])
            }
            if let projectPath {
                arguments.append(contentsOf: ["--project-path", projectPath])
            }
            return ThreadResumePlan(arguments: arguments, interactive: true)
        case .claude:
            guard claudeSessionID(for: prompt) != nil else { return nil }
            var arguments = [
                "open-thread",
                "--provider", prompt.provider.rawValue,
                "--source-path", sourcePath
            ]
            if let contextID = normalizedContextID(prompt.sourceContextID) {
                arguments.append(contentsOf: ["--context-id", contextID])
            }
            if let projectPath {
                arguments.append(contentsOf: ["--project-path", projectPath])
            }
            return ThreadResumePlan(arguments: arguments, interactive: true)
        case .opencode:
            guard openCodeSessionID(for: prompt) != nil else { return nil }
            var arguments = [
                "open-thread",
                "--provider", prompt.provider.rawValue,
                "--source-path", sourcePath
            ]
            if let contextID = normalizedContextID(prompt.sourceContextID) {
                arguments.append(contentsOf: ["--context-id", contextID])
            }
            if let projectPath {
                arguments.append(contentsOf: ["--project-path", projectPath])
            }
            return ThreadResumePlan(arguments: arguments, interactive: true)
        case .cursor, .copilot:
            guard let projectPath else { return nil }
            var arguments = [
                "open-thread",
                "--provider", prompt.provider.rawValue,
                "--source-path", sourcePath,
                "--project-path", projectPath
            ]
            if let contextID = normalizedContextID(prompt.sourceContextID) {
                arguments.append(contentsOf: ["--context-id", contextID])
            }
            return ThreadResumePlan(arguments: arguments, interactive: false)
        case .antigravity:
            var arguments = [
                "open-thread",
                "--provider", prompt.provider.rawValue,
                "--source-path", sourcePath
            ]
            if let contextID = normalizedContextID(prompt.sourceContextID) {
                arguments.append(contentsOf: ["--context-id", contextID])
            }
            if let projectPath {
                arguments.append(contentsOf: ["--project-path", projectPath])
            }
            return ThreadResumePlan(arguments: arguments, interactive: false)
        }
    }

    private func codexSessionID(for prompt: ImportedPrompt) -> String? {
        if let explicit = normalizedContextID(prompt.sourceContextID), explicit.contains("/") == false {
            return explicit
        }
        guard let raw = try? String(contentsOfFile: prompt.sourcePath, encoding: .utf8) else {
            return nil
        }
        for line in raw.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "session_meta",
                  let payload = object["payload"] as? [String: Any],
                  let id = payload["id"] as? String,
                  normalizedContextID(id) != nil
            else {
                continue
            }
            return id
        }
        return nil
    }

    private func claudeSessionID(for prompt: ImportedPrompt) -> String? {
        if let explicit = normalizedContextID(prompt.sourceContextID), explicit.contains("/") == false {
            return explicit
        }
        return claudeSessionIDFromFilename(prompt.sourcePath)
    }

    private func openCodeSessionID(for prompt: ImportedPrompt) -> String? {
        if let explicit = normalizedContextID(prompt.sourceContextID),
           explicit.contains("/") == false,
           explicit.hasPrefix("session:") == false {
            return explicit
        }
        let candidate = normalizedContextID(prompt.sourceContextID) ?? prompt.sourcePath
        let prefix = "session:"
        let suffix = ":prompt"
        let trimmed = candidate.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? candidate
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix), trimmed.count > prefix.count + suffix.count else {
            return nil
        }
        return String(trimmed.dropFirst(prefix.count).dropLast(suffix.count))
    }

    private func claudeSessionIDFromFilename(_ sourcePath: String) -> String? {
        let url = URL(fileURLWithPath: sourcePath)
        guard url.pathExtension.lowercased() == "jsonl" else { return nil }
        let identifier = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? nil : identifier
    }

    private func codebookCLIInvocation() -> [String]? {
        let fileManager = FileManager.default
        if let helperURL = bundledCLIHelperURL(), fileManager.isExecutableFile(atPath: helperURL.path) {
            return [helperURL.path]
        }

        let installedURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("codebook", isDirectory: false)
        if fileManager.isExecutableFile(atPath: installedURL.path) {
            return [installedURL.path]
        }

        if commandExists(named: "codebook") {
            return ["codebook"]
        }

        return nil
    }

    private func bundledCLIHelperURL() -> URL? {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("codebook-cli", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: helperURL.path) ? helperURL : nil
    }

    private func commandExists(named command: String) -> Bool {
        let fileManager = FileManager.default

        if command.contains("/") {
            return fileManager.isExecutableFile(atPath: command)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let searchPaths = pathValue
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        let home = fileManager.homeDirectoryForCurrentUser.path
        let fallbackPaths = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        // nvm / fnm / volta / n — cover every common Node version manager
        let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"] ?? "\(home)/.nvm"
        let nodeManagerPaths = resolveNodeManagerBinPaths(nvmDir: nvmDir, home: home)
        let cargoBin = "\(home)/.cargo/bin"

        let allPaths = searchPaths + fallbackPaths + nodeManagerPaths + [cargoBin]
        for directory in Array(NSOrderedSet(array: allPaths)) as? [String] ?? allPaths {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(command, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return true
            }
        }

        return false
    }

    /// Resolves bin directories for nvm, fnm, volta, and n node version managers.
    private func resolveNodeManagerBinPaths(nvmDir: String, home: String) -> [String] {
        let fileManager = FileManager.default
        var paths: [String] = []

        // nvm: ~/.nvm/versions/node/*/bin — pick the latest or current default
        let nvmVersionsDir = "\(nvmDir)/versions/node"
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmVersionsDir) {
            let sorted = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            for version in sorted {
                let binPath = "\(nvmVersionsDir)/\(version)/bin"
                if fileManager.isExecutableFile(atPath: binPath) || fileManager.fileExists(atPath: binPath) {
                    paths.append(binPath)
                    break
                }
            }
        }

        // fnm: ~/.local/share/fnm/node-versions/*/installation/bin
        let fnmVersionsDir = "\(home)/.local/share/fnm/node-versions"
        if let versions = try? fileManager.contentsOfDirectory(atPath: fnmVersionsDir) {
            let sorted = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            for version in sorted {
                let binPath = "\(fnmVersionsDir)/\(version)/installation/bin"
                if fileManager.fileExists(atPath: binPath) {
                    paths.append(binPath)
                    break
                }
            }
        }

        // volta
        let voltaBin = "\(home)/.volta/bin"
        if fileManager.fileExists(atPath: voltaBin) {
            paths.append(voltaBin)
        }

        // npm global (default prefix)
        let npmPrefix = "/usr/local/lib/node_modules/.bin"
        if fileManager.fileExists(atPath: npmPrefix) {
            paths.append(npmPrefix)
        }

        return paths
    }

    private func providerCommandName(for provider: IntegrationProvider) -> String? {
        switch provider {
        case .codex:
            return "codex"
        case .claude:
            return "claude"
        case .opencode:
            return "opencode"
        case .cursor, .copilot, .antigravity:
            return nil
        }
    }

    private func canLaunchThreadPlan(_ plan: ThreadResumePlan, for provider: IntegrationProvider) -> Bool {
        if plan.interactive {
            guard let providerCommand = providerCommandName(for: provider) else {
                return false
            }
            return commandExists(named: providerCommand)
        }

        switch provider {
        case .cursor:
            return commandExists(named: "cursor")
        case .copilot:
            return commandExists(named: "code") || appExists(named: "Visual Studio Code")
        case .antigravity:
            return appExists(named: "Antigravity")
        case .codex, .claude, .opencode:
            return false
        }
    }

    private func appExists(named appName: String) -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/\(appName).app")
    }

    private func terminalResumeCommand(codebookInvocation: [String], arguments: [String]) -> String {
        (codebookInvocation + arguments).map(shellQuoted).joined(separator: " ")
    }

    private func launchInTerminal(_ command: String) throws {
        let script = """
        tell application "Terminal"
            do script \(appleScriptStringLiteral(command))
            activate
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ActionError.terminalLaunchFailed("Failed to launch Terminal for thread resume.")
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ActionError.terminalLaunchFailed(
                stderr.isEmpty ? "Failed to launch Terminal for thread resume." : stderr
            )
        }
    }

    private func launchCodebookCommand(_ command: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ActionError.terminalLaunchFailed("Failed to launch Open Thread.")
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ActionError.terminalLaunchFailed(
                stderr.isEmpty ? "Failed to launch Open Thread." : stderr
            )
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func automateNewThread(in provider: IntegrationProvider, text: String) throws {
        guard let appURL = applicationURL(for: provider) else {
            throw ActionError.missingApplication(provider)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        let appName = applicationName(for: provider) ?? provider.title
        let script = """
        tell application "\(appName)" to activate
        delay 0.35
        tell application "System Events"
            tell process "\(appName)"
                keystroke "n" using command down
                delay 0.15
                keystroke "v" using command down
                delay 0.1
                key code 36
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ActionError.automationFailed("Could not automate \(provider.title).")
        }

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ActionError.automationFailed(message.isEmpty ? "Could not automate \(provider.title)." : message)
        }
    }

    /// Fork to Claude Code CLI by piping prompt text via `claude --print` with `--resume` flag to start a fresh session.
    private func forkToClaude(text: String, projectPath: String?) throws {
        guard commandExists(named: "claude") else {
            throw ActionError.missingCLI(.claude)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        var command = "claude"
        if let projectPath, !projectPath.isEmpty {
            command += " -p \(shellQuoted(projectPath))"
        }
        command += " \(shellQuoted(text))"

        try launchInTerminal(command)
    }

    /// Fork to VS Code / Copilot by opening a workspace and pasting via automation.
    private func forkToCopilot(text: String, projectPath: String?) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if commandExists(named: "code") {
            var args = [String]()
            if let projectPath, !projectPath.isEmpty {
                args.append(shellQuoted(projectPath))
            }
            let codeCommand = "code \(args.joined(separator: " "))"
            let script = """
            do shell script "\(codeCommand.replacingOccurrences(of: "\"", with: "\\\""))"
            delay 1.0
            tell application "Visual Studio Code" to activate
            delay 0.3
            tell application "System Events"
                tell process "Code"
                    keystroke "i" using {control down, shift down}
                    delay 0.3
                    keystroke "v" using command down
                    delay 0.1
                    key code 36
                end tell
            end tell
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw ActionError.automationFailed("Could not automate Copilot via VS Code.")
            }

            guard process.terminationStatus == 0 else {
                let message = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ActionError.automationFailed(message.isEmpty ? "Could not automate Copilot." : message)
            }
        } else if let appURL = applicationURL(for: .copilot) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

            let script = """
            tell application "Visual Studio Code" to activate
            delay 0.8
            tell application "System Events"
                tell process "Code"
                    keystroke "i" using {control down, shift down}
                    delay 0.3
                    keystroke "v" using command down
                    delay 0.1
                    key code 36
                end tell
            end tell
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw ActionError.automationFailed("Could not automate Copilot.")
            }

            guard process.terminationStatus == 0 else {
                let message = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ActionError.automationFailed(message.isEmpty ? "Could not automate Copilot." : message)
            }
        } else {
            throw ActionError.missingApplication(.copilot)
        }
    }
}

private struct ThreadResumePlan {
    let arguments: [String]
    let interactive: Bool
}
