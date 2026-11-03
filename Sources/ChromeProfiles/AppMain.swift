import AppKit

/// Entry point. The app is a menu bar accessory: no Dock icon, no main window.
@main
enum ChromeProfilesMain {
    @MainActor
    static func main() {
        // Read-only report, used for bug reports and quick checks in a terminal.
        if CommandLine.arguments.contains("--diagnostics") {
            Diagnostics.run()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
