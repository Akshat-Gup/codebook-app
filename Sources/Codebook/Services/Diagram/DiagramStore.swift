import Foundation

struct DiagramStore {
    private let policy = RuntimePolicy.shared
    private let storeURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let fileManager = FileManager.default
        if let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let directory = support.appendingPathComponent("Codebook", isDirectory: true)
            SecureFileStore.prepareDirectory(directory)
            storeURL = directory.appendingPathComponent("saved-diagrams.json")
        } else {
            storeURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Codebook/saved-diagrams.json")
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        SecureFileStore.hardenFileIfPresent(at: storeURL)
    }

    func load() -> [SavedDiagram] {
        guard policy.persistentStorageEnabled else { return [] }
        guard let data = try? Data(contentsOf: storeURL),
              let diagrams = try? decoder.decode([SavedDiagram].self, from: data)
        else {
            return []
        }
        return diagrams
    }

    func save(_ diagrams: [SavedDiagram]) {
        guard policy.persistentStorageEnabled else { return }
        guard let data = try? encoder.encode(diagrams) else { return }
        try? SecureFileStore.write(data, to: storeURL)
    }
}
