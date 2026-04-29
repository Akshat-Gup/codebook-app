import Foundation

struct IntegrationScanCacheStore {
    struct Entry: Codable, Sendable {
        let fingerprint: String
        let prompts: [ImportedPrompt]
    }

    private let policy = RuntimePolicy.shared
    private let cacheURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let fileManager = FileManager.default
        if let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let directory = support.appendingPathComponent("Codebook", isDirectory: true)
            SecureFileStore.prepareDirectory(directory)
            cacheURL = directory.appendingPathComponent("integration-scan-cache.json")
        } else {
            cacheURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Codebook/integration-scan-cache.json")
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        SecureFileStore.hardenFileIfPresent(at: cacheURL)
    }

    func load() -> [String: Entry] {
        guard policy.persistentStorageEnabled else { return [:] }
        guard let data = try? Data(contentsOf: cacheURL),
              let entries = try? decoder.decode([String: Entry].self, from: data)
        else {
            return [:]
        }
        return entries
    }

    func save(_ entries: [String: Entry]) {
        guard policy.persistentStorageEnabled else { return }
        guard let data = try? encoder.encode(entries) else { return }
        try? SecureFileStore.write(data, to: cacheURL)
    }

    func seedIfNeeded(from prompts: [ImportedPrompt]) {
        guard policy.persistentStorageEnabled else { return }
        guard !prompts.isEmpty, load().isEmpty else { return }

        let grouped = Dictionary(grouping: prompts) { prompt in
            IntegrationScanner.sourceCacheKey(provider: prompt.provider, sourcePath: prompt.sourcePath)
        }

        let entries = grouped.reduce(into: [String: Entry]()) { partialResult, element in
            let key = element.key
            let prompts = element.value
            guard let first = prompts.first,
                  let fingerprint = fingerprint(for: first.provider, sourcePath: first.sourcePath)
            else {
                return
            }
            partialResult[key] = Entry(fingerprint: fingerprint, prompts: prompts)
        }

        guard !entries.isEmpty else { return }
        save(entries)
    }

    func removeProviders(_ providers: Set<IntegrationProvider>) {
        guard !providers.isEmpty else { return }
        let retained = load().filter { key, entry in
            !matchesAnyProvider(key: key, entry: entry, providers: providers)
        }
        save(retained)
    }

    private func matchesAnyProvider(key: String, entry: Entry, providers: Set<IntegrationProvider>) -> Bool {
        if let provider = entry.prompts.first?.provider {
            return providers.contains(provider)
        }
        return providers.contains { provider in
            key.contains(":\(provider.rawValue):") || key.contains(":\(provider.rawValue)-")
        }
    }

    private func fingerprint(for provider: IntegrationProvider, sourcePath: String) -> String? {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        switch provider {
        case .cursor:
            let workspaceURL = sourceURL.deletingLastPathComponent().appendingPathComponent("workspace.json")
            return compositeFingerprint(for: [sourceURL, workspaceURL])
        case .codex, .claude, .copilot, .opencode:
            return fileFingerprint(for: sourceURL)
        case .antigravity:
            let taskURL = sourceURL.deletingLastPathComponent().appendingPathComponent("task.md", isDirectory: false)
            return compositeFingerprint(for: [sourceURL, taskURL])
        }
    }

    private func fileFingerprint(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return "\(Int64(modifiedAt.timeIntervalSince1970)):\(size)"
    }

    private func compositeFingerprint(for urls: [URL]) -> String? {
        let components = urls.compactMap { url -> String? in
            if !FileManager.default.fileExists(atPath: url.path) {
                return "missing:\(url.lastPathComponent)"
            }
            return fileFingerprint(for: url)
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "|")
    }
}
