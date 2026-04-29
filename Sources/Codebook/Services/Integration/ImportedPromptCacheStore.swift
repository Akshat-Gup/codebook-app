import Foundation

struct ImportedPromptCacheStore {
    private let policy = RuntimePolicy.shared
    private let cacheURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let fileManager = FileManager.default
        if let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let directory = support.appendingPathComponent("Codebook", isDirectory: true)
            SecureFileStore.prepareDirectory(directory)
            cacheURL = directory.appendingPathComponent("imported-prompts.json")
        } else {
            cacheURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Codebook/imported-prompts.json")
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        SecureFileStore.hardenFileIfPresent(at: cacheURL)
    }

    func load(allowedProviders: Set<IntegrationProvider>? = nil) -> [ImportedPrompt] {
        guard policy.persistentStorageEnabled else { return [] }
        guard let data = try? Data(contentsOf: cacheURL),
              let prompts = try? decoder.decode([ImportedPrompt].self, from: data)
        else {
            return []
        }
        guard let allowedProviders else { return prompts }
        return prompts.filter { allowedProviders.contains($0.provider) }
    }

    func save(_ prompts: [ImportedPrompt]) {
        guard policy.persistentStorageEnabled else { return }
        guard let data = try? encoder.encode(prompts) else { return }
        try? SecureFileStore.write(data, to: cacheURL)
    }

    func removeProviders(_ providers: Set<IntegrationProvider>) {
        guard !providers.isEmpty else { return }
        let retained = load().filter { !providers.contains($0.provider) }
        save(retained)
    }

    func isFresh(maxAge: TimeInterval) -> Bool {
        guard policy.persistentStorageEnabled else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return false
        }
        return Date().timeIntervalSince(modifiedAt) <= maxAge
    }
}
