import AppKit
import ProfileKit

/// Small, on-demand settings window. It only shows where profiles live and
/// lets the user open or change that folder; there is no settings database.
@MainActor
final class PreferencesWindowController: NSWindowController {

    private let preferences: Preferences
    private let onRootChanged: () -> Void

    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let kindLabel = NSTextField(labelWithString: "")

    init(preferences: Preferences, onRootChanged: @escaping () -> Void) {
        self.preferences = preferences
        self.onRootChanged = onRootChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "偏好设置"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildContent()
        refreshLabels()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "配置根目录")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        pathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pathLabel.textColor = .labelColor
        pathLabel.isSelectable = true

        kindLabel.font = .systemFont(ofSize: 11)
        kindLabel.textColor = .secondaryLabelColor

        let openButton = NSButton(title: "在访达中打开", target: self, action: #selector(openRoot(_:)))
        let changeButton = NSButton(title: "更改…", target: self, action: #selector(changeRoot(_:)))
        let resetButton = NSButton(title: "恢复默认", target: self, action: #selector(resetRoot(_:)))

        for button in [openButton, changeButton, resetButton] {
            button.bezelStyle = .rounded
        }

        let buttonRow = NSStackView(views: [openButton, changeButton, resetButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let explanation = NSTextField(wrappingLabelWithString:
            "根目录下的每一个一级子目录都会被当作一个独立的 Chrome 用户数据目录，启动时作为 --user-data-dir 传入。\n应用不会读取或修改 Chrome 的 Local State、Preferences 等内部文件，切换到新目录也不会移动或删除旧目录中的配置。"
        )
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor

        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: "Chrome Profiles \(version) · 原生 AppKit 菜单栏工具")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [
            heading, pathLabel, kindLabel, buttonRow,
            makeSeparator(), explanation, versionLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(4, after: heading)
        stack.setCustomSpacing(6, after: pathLabel)

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func refreshLabels() {
        let url = preferences.rootURL
        pathLabel.stringValue = (url.path as NSString).abbreviatingWithTildeInPath
        kindLabel.stringValue = preferences.isUsingDefaultRoot
            ? "当前使用默认目录"
            : "当前使用自定义目录（默认目录不受影响）"
    }

    // MARK: - Actions

    @objc private func openRoot(_ sender: Any?) {
        do {
            try ProfileStore(rootURL: preferences.rootURL).ensureRootExists()
            NSWorkspace.shared.open(preferences.rootURL)
        } catch {
            Prompts.show(error: error)
        }
    }

    @objc private func changeRoot(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择一个目录作为配置根目录"

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try preferences.setRootURL(url)
            refreshLabels()
            onRootChanged()
        } catch {
            Prompts.show(error: error)
        }
    }

    @objc private func resetRoot(_ sender: Any?) {
        preferences.resetRoot()
        refreshLabels()
        onRootChanged()
    }
}
