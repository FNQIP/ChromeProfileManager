import AppKit

/// Native alert helpers. Every failure reaches the user through one of these,
/// never through stdout.
@MainActor
enum Prompts {

    static func show(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = messageText(for: error)

        if let localized = error as? LocalizedError,
           let suggestion = localized.recoverySuggestion {
            alert.informativeText = suggestion
        }

        alert.addButton(withTitle: "好")
        run(alert)
    }

    static func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        run(alert)
    }

    /// Returns true when the user confirms the destructive action.
    static func confirmDestructive(title: String,
                                   message: String,
                                   confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message

        let confirmButton = alert.addButton(withTitle: confirmTitle)
        confirmButton.hasDestructiveAction = true
        alert.addButton(withTitle: "取消")

        activateApp()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Single-line name input. Returns nil when the user cancels.
    static func askForName(title: String,
                           message: String,
                           confirmTitle: String,
                           initialValue: String) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initialValue
        field.placeholderString = "例如：工作"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        activateApp()
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    // MARK: - Helpers

    private static func run(_ alert: NSAlert) {
        activateApp()
        alert.runModal()
    }

    private static func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func messageText(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return (error as NSError).localizedDescription
    }
}
