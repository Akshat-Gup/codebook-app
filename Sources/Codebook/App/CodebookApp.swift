import AppKit
import SwiftUI

@main
struct CodebookApp: App {
    @StateObject private var model: AppModel
    @StateObject private var updaterController: SparkleUpdaterController
    @State private var hasPerformedOneTimeSetup = false

    init() {
        let updaterController = SparkleUpdaterController()
        _updaterController = StateObject(wrappedValue: updaterController)
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                                .environmentObject(model)
                                .environmentObject(updaterController)
                                .frame(minWidth: 1240, minHeight: 760)
                .background(.ultraThinMaterial)
                .onAppear {
                    guard !hasPerformedOneTimeSetup else { return }
                    hasPerformedOneTimeSetup = true
                    DispatchQueue.main.async {
                        if let iconURL = AppIconLocator.url,
                           let iconImage = NSImage(contentsOf: iconURL) {
                            NSApp.applicationIconImage = iconImage
                        }
                        if model.isCLIEnabled {
                            do {
                                try CLIInstaller().installBundledCLIIfNeeded(
                                    bundleURL: Bundle.main.bundleURL,
                                    logger: RuntimeLogger.shared
                                )
                            } catch {
                                RuntimeLogger.shared.error("Failed to install CLI launcher", error: error)
                            }
                        }
                        updaterController.startUpdaterIfNeeded()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Search") {
                    model.requestSearchFocus()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    Task { await model.refresh(forceScan: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])

                if model.isDiagnosticsEnabled {
                    Button("Open Diagnostics Folder") {
                        model.openDiagnosticsFolder()
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                }

                Button("Check for Updates…") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }
}

private enum AppIconLocator {
    static var url: URL? {
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static var candidates: [URL] {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repoRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns"),
            repoRootURL.appendingPathComponent("Assets/AppIcon.icns")
        ].compactMap { $0 }
    }
}
