import AppKit
import ProfileKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let preferences = Preferences()
    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ProfileStore(rootURL: preferences.rootURL)
        let service = ProfileService(store: store)

        statusMenuController = StatusMenuController(service: service, preferences: preferences)

        // Requirement: the root is created on launch when it does not exist.
        // A failure is reported to the user instead of being written to a log.
        do {
            try store.ensureRootExists()
        } catch {
            Prompts.show(error: error)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Quitting the menu bar app must never quit Chrome.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
