import Foundation

struct ProjectPathResolver {
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let manualFoldersKey = "codebook.manualFolders"

    func resolve(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let normalized = normalize(path)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: normalized, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? normalized : URL(fileURLWithPath: normalized).deletingLastPathComponent().path
        }

        let basename = URL(fileURLWithPath: normalized).lastPathComponent
        guard !basename.isEmpty else { return nil }
        return findCandidate(named: basename)
    }

    private func normalize(_ path: String) -> String {
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL {
            return url.path
        }
        return NSString(string: path).expandingTildeInPath
    }

    private func findCandidate(named name: String) -> String? {
        for root in searchRoots() {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            if root.lastPathComponent.lowercased() == name.lowercased() {
                return root.path
            }
            if let candidate = shallowMatch(in: root, targetName: name) {
                return candidate
            }
        }
        return nil
    }

    private func searchRoots() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let manualRoots = (defaults.stringArray(forKey: manualFoldersKey) ?? []).map {
            URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true)
        }
        let defaultsRoots = [
            home.appendingPathComponent("Documents/GitHub", isDirectory: true),
            home.appendingPathComponent("Code", isDirectory: true),
            home.appendingPathComponent("Projects", isDirectory: true),
            home.appendingPathComponent("Developer", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true)
        ]
        var seen = Set<String>()
        return (manualRoots + defaultsRoots).filter { seen.insert($0.path).inserted }
    }

    private func shallowMatch(in root: URL, targetName: String) -> String? {
        let target = targetName.lowercased()
        let levelOne = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

        for url in levelOne {
            if url.lastPathComponent.lowercased() == target {
                return url.path
            }
        }

        for url in levelOne {
            guard isDirectory(url) else { continue }
            let levelTwo = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for nested in levelTwo where nested.lastPathComponent.lowercased() == target {
                return nested.path
            }
        }

        return nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) == true
    }
}
