import Foundation

struct RepoAutomationStore {
    private let policy: RuntimePolicy
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard, policy: RuntimePolicy = .shared) {
        self.policy = policy
        let fileManager = FileManager.default
        if let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let directory = support.appendingPathComponent("Codebook", isDirectory: true)
            SecureFileStore.prepareDirectory(directory)
            self.storageURL = directory.appendingPathComponent("repo-automation-settings.json")
        } else {
            self.storageURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Codebook/repo-automation-settings.json")
        }
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    func allSettings() -> [String: RepoAutomationSettings] {
        guard policy.persistentStorageEnabled else { return [:] }
        guard let data = try? Data(contentsOf: storageURL),
              let settings = try? decoder.decode([String: RepoAutomationSettings].self, from: data)
        else {
            return [:]
        }
        return settings
    }

    func settings(for gitRoot: String) -> RepoAutomationSettings? {
        allSettings()[normalizedKey(gitRoot)]
    }

    func save(_ settings: RepoAutomationSettings, for gitRoot: String) {
        guard policy.persistentStorageEnabled else { return }
        var current = allSettings()
        current[normalizedKey(gitRoot)] = settings.normalized()
        persist(current)
    }

    func remove(for gitRoot: String) {
        guard policy.persistentStorageEnabled else { return }
        var current = allSettings()
        current.removeValue(forKey: normalizedKey(gitRoot))
        persist(current)
    }

    func configuredGitRoots() -> [String] {
        allSettings().keys.sorted()
    }

    private func persist(_ settings: [String: RepoAutomationSettings]) {
        guard let data = try? encoder.encode(settings) else { return }
        try? SecureFileStore.write(data, to: storageURL)
    }

    private func normalizedKey(_ gitRoot: String) -> String {
        URL(fileURLWithPath: gitRoot).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

extension RepoAutomationSettings {
    func normalized() -> RepoAutomationSettings {
        var copy = self
        copy.promptStorePath = copy.promptStorePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.promptStorePath.isEmpty {
            copy.promptStorePath = "prompts"
        }
        copy.trackedProviders = Array(Set(copy.trackedProviders)).sorted { $0.rawValue < $1.rawValue }
        return copy
    }
}
