import AppKit
import Foundation
import Sparkle

@MainActor
final class SparkleUpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var statusMessage = "Sparkle updater is configured."

    let updaterController: SPUStandardUpdaterController

    private var canCheckObservation: NSKeyValueObservation?

    init(startingUpdater: Bool = false) {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController

        canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// Call after the SwiftUI view graph is ready (e.g. in .onAppear)
    /// to avoid re-entrant AttributeGraph mutations from Sparkle's NSAlert.
    func startUpdaterIfNeeded() {
        guard !updaterController.updater.sessionInProgress else { return }
        try? updaterController.updater.start()
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    var feedURL: URL? {
        updater.feedURL
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func openFeedURL() {
        guard let feedURL else { return }
        NSWorkspace.shared.open(feedURL)
    }
}
