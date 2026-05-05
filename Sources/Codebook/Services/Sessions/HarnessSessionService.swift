import AppKit
import Foundation

struct HarnessSessionStatus: Equatable {
    var isInstalled: Bool
    var isRunning: Bool
    var isKeepingAwake: Bool
    var activeProcessName: String?
    var watchedProcessNames: [String]
    var logPath: String
}

struct HarnessSessionService {
    let fileManager: FileManager
    let homeDirectory: URL
    let label: String

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        label: String = "com.codebook.harness-sessions"
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.label = label
    }

    var defaultProcessNames: [String] {
        IntegrationProvider.allCases.map(\.rawValue)
    }

    private var supportDirectory: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Codebook", isDirectory: true)
    }

    var scriptURL: URL {
        supportDirectory.appendingPathComponent("harness-session-watcher.sh", isDirectory: false)
    }

    var plistURL: URL {
        homeDirectory.appendingPathComponent("Library/LaunchAgents/\(label).plist", isDirectory: false)
    }

    var logURL: URL {
        homeDirectory.appendingPathComponent("Library/Logs/codebook-harness-sessions.log", isDirectory: false)
    }

    func status(processNames: [String]? = nil) -> HarnessSessionStatus {
        let watchedProcessNames = normalizedProcessNames(processNames)
        let activeName = activeHarnessProcessName(in: watchedProcessNames)
        let watcherPID = watcherProcessPID()
        return HarnessSessionStatus(
            isInstalled: fileManager.fileExists(atPath: plistURL.path),
            isRunning: launchAgentLoaded(),
            isKeepingAwake: caffeinateIsHeld(watcherPID: watcherPID),
            activeProcessName: activeName,
            watchedProcessNames: watchedProcessNames,
            logPath: logURL.path
        )
    }

    func install(
        processNames: [String]? = nil,
        pollIntervalSeconds: Int = 5,
        mode: HarnessSessionMode = .agentSessions,
        customDurationSeconds: Int = 3 * 60 * 60,
        keepDisplayAwake: Bool = false,
        powerAdapterOnly: Bool = false,
        loadLaunchAgent: Bool = true
    ) throws {
        let watchedProcessNames = normalizedProcessNames(processNames)
        let pollIntervalSeconds = max(3, min(pollIntervalSeconds, 300))
        try writeWatcherScript()
        try writeLaunchAgent(
            processNames: watchedProcessNames,
            pollIntervalSeconds: pollIntervalSeconds,
            mode: mode,
            customDurationSeconds: customDurationSeconds,
            keepDisplayAwake: keepDisplayAwake,
            powerAdapterOnly: powerAdapterOnly
        )
        guard loadLaunchAgent else { return }
        _ = try? Shell.run("/bin/launchctl", arguments: ["unload", plistURL.path], timeout: 2)
        _ = try Shell.run("/bin/launchctl", arguments: ["load", "-w", plistURL.path], timeout: 4)
    }

    func uninstall(unloadLaunchAgent: Bool = true) throws {
        if fileManager.fileExists(atPath: plistURL.path) {
            if unloadLaunchAgent {
                _ = try? Shell.run("/bin/launchctl", arguments: ["unload", plistURL.path], timeout: 2)
            }
            try fileManager.removeItem(at: plistURL)
        }
        // Kill the watcher script; its SIGTERM trap releases the held caffeinate
        // child, so we don't need a broad `pkill -x caffeinate` (which would
        // terminate unrelated `caffeinate` processes the user is running).
        _ = try? Shell.run("/usr/bin/pkill", arguments: ["-f", "\(scriptURL.path) run"], timeout: 2)
        // Remove the watcher script itself so no stale script lingers after uninstall.
        if fileManager.fileExists(atPath: scriptURL.path) {
            try? fileManager.removeItem(at: scriptURL)
        }
    }

    func openLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    private func writeWatcherScript() throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private func writeLaunchAgent(
        processNames: [String],
        pollIntervalSeconds: Int,
        mode: HarnessSessionMode,
        customDurationSeconds: Int,
        keepDisplayAwake: Bool,
        powerAdapterOnly: Bool
    ) throws {
        let launchAgents = plistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        try plistBody(
            processNames: processNames,
            pollIntervalSeconds: pollIntervalSeconds,
            mode: mode,
            customDurationSeconds: customDurationSeconds,
            keepDisplayAwake: keepDisplayAwake,
            powerAdapterOnly: powerAdapterOnly
        ).write(to: plistURL, atomically: true, encoding: .utf8)
    }

    private func launchAgentLoaded() -> Bool {
        guard let result = try? Shell.run("/bin/launchctl", arguments: ["list"], timeout: 2) else { return false }
        return result.stdout
            .split(separator: "\n")
            .contains { $0.split(whereSeparator: \.isWhitespace).last == Substring(label) }
    }

    private func caffeinateIsHeld(watcherPID: String?) -> Bool {
        // Only count caffeinate spawned by our watcher script, so other apps'
        // caffeinate processes (or a manual `caffeinate -i` from the user) don't
        // make us claim we're holding the assertion.
        guard let watcherPID, !watcherPID.isEmpty else { return false }
        guard let result = try? Shell.run(
            "/usr/bin/pgrep",
            arguments: ["-P", watcherPID, "-x", "caffeinate"],
            timeout: 2
        ) else { return false }
        return result.status == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func watcherProcessPID() -> String? {
        guard let result = try? Shell.run(
            "/usr/bin/pgrep",
            arguments: ["-f", "\(scriptURL.path) run"],
            timeout: 2
        ) else { return nil }
        guard result.status == 0 else { return nil }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
    }

    private func activeHarnessProcessName(in watchedNames: [String]) -> String? {
        for name in watchedNames {
            if let result = try? Shell.run("/usr/bin/pgrep", arguments: ["-x", name], timeout: 1),
               result.status == 0 {
                return name
            }
        }
        return nil
    }

    private func normalizedProcessNames(_ processNames: [String]?) -> [String] {
        let names = processNames ?? defaultProcessNames
        let filtered = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(" ") && !$0.contains("\"") }
        return filtered.isEmpty ? defaultProcessNames : Array(Set(filtered)).sorted()
    }

    private var processListLiteral: String {
        defaultProcessNames.map { "\"\($0)\"" }.joined(separator: " ")
    }

    private var scriptBody: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail

        LOG_FILE="$HOME/Library/Logs/codebook-harness-sessions.log"
        POLL_INTERVAL="${CODEBOOK_SESSION_POLL_INTERVAL:-5}"
        MODE="${CODEBOOK_SESSION_MODE:-agentSessions}"
        DURATION_SECONDS="${CODEBOOK_SESSION_DURATION_SECONDS:-}"
        KEEP_DISPLAY_AWAKE="${CODEBOOK_SESSION_KEEP_DISPLAY_AWAKE:-false}"
        POWER_ADAPTER_ONLY="${CODEBOOK_SESSION_POWER_ADAPTER_ONLY:-false}"
        PROCESSES=(${CODEBOOK_SESSION_PROCESSES:-\(processListLiteral)})

        log() {
          mkdir -p "$(dirname "$LOG_FILE")"
          printf '%s %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"
        }

        any_harness_running() {
          ACTIVE_NAME=""
          for name in "${PROCESSES[@]}"; do
            if pgrep -x "$name" >/dev/null 2>&1; then
              ACTIVE_NAME="$name"
              return 0
            fi
          done
          return 1
        }

        CAFF_PID=""
        cleanup() {
          if [[ -n "$CAFF_PID" ]] && kill -0 "$CAFF_PID" 2>/dev/null; then
            kill "$CAFF_PID" 2>/dev/null || true
            log "stopped caffeinate on watcher exit"
          fi
          exit 0
        }
        trap cleanup INT TERM

        STARTED_AT="$(date +%s)"
        log "session watcher start (mode=$MODE, processes=${PROCESSES[*]})"

        duration_expired() {
          if [[ -z "$DURATION_SECONDS" ]]; then
            return 1
          fi
          local now
          now="$(date +%s)"
          [[ $((now - STARTED_AT)) -ge "$DURATION_SECONDS" ]]
        }

        should_keep_awake() {
          if duration_expired; then
            return 1
          fi
          if [[ "$POWER_ADAPTER_ONLY" == "true" ]] && ! pmset -g batt | head -n 1 | grep -q "AC Power"; then
            return 1
          fi
          case "$MODE" in
            agentSessions) any_harness_running ;;
            *) ACTIVE_NAME="$MODE"; return 0 ;;
          esac
        }

        while true; do
          if should_keep_awake; then
            if [[ -z "$CAFF_PID" ]] || ! kill -0 "$CAFF_PID" 2>/dev/null; then
              if [[ "$KEEP_DISPLAY_AWAKE" == "true" ]]; then
                caffeinate -di &
              else
                caffeinate -i &
              fi
              CAFF_PID=$!
              log "started caffeinate; active: $ACTIVE_NAME"
            fi
          else
            if [[ -n "$CAFF_PID" ]] && kill -0 "$CAFF_PID" 2>/dev/null; then
              kill "$CAFF_PID" 2>/dev/null || true
              CAFF_PID=""
              log "stopped caffeinate; no active sessions"
            fi
          fi
          sleep "$POLL_INTERVAL"
        done
        """
    }

    private func plistBody(
        processNames: [String],
        pollIntervalSeconds: Int,
        mode: HarnessSessionMode,
        customDurationSeconds: Int,
        keepDisplayAwake: Bool,
        powerAdapterOnly: Bool
    ) -> String {
        let joined = processNames.joined(separator: " ")
        let resolvedDuration = mode == .custom ? max(60, min(customDurationSeconds, 30 * 24 * 60 * 60)) : mode.durationSeconds
        let duration = resolvedDuration.map(String.init) ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(scriptURL.path)</string>
                <string>run</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>EnvironmentVariables</key>
            <dict>
                <key>CODEBOOK_SESSION_PROCESSES</key>
                <string>\(joined)</string>
                <key>CODEBOOK_SESSION_POLL_INTERVAL</key>
                <string>\(pollIntervalSeconds)</string>
                <key>CODEBOOK_SESSION_MODE</key>
                <string>\(mode.rawValue)</string>
                <key>CODEBOOK_SESSION_DURATION_SECONDS</key>
                <string>\(duration)</string>
                <key>CODEBOOK_SESSION_KEEP_DISPLAY_AWAKE</key>
                <string>\(keepDisplayAwake ? "true" : "false")</string>
                <key>CODEBOOK_SESSION_POWER_ADAPTER_ONLY</key>
                <string>\(powerAdapterOnly ? "true" : "false")</string>
            </dict>
            <key>StandardOutPath</key>
            <string>\(logURL.deletingPathExtension().path).out.log</string>
            <key>StandardErrorPath</key>
            <string>\(logURL.deletingPathExtension().path).err.log</string>
        </dict>
        </plist>
        """
    }
}
