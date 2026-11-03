import AppKit
import ProfileKit
import ProfileUI

/// Owns the status item and rebuilds the menu from a fresh snapshot every time
/// the menu is opened, so folders created or removed outside the app show up
/// immediately.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {

    private var service: ProfileService
    private let preferences: Preferences

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var preferencesWindowController: PreferencesWindowController?

    init(service: ProfileService, preferences: Preferences) {
        self.service = service
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let icon = MenuBarIcon.make()
        icon.isTemplate = true
        button.image = icon
        button.imagePosition = .imageOnly
        button.toolTip = "Chrome Profile Manager"
        button.setAccessibilityLabel("Chrome Profile Manager")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let model = MenuModel.make(from: service.snapshot())

        for row in model.rows {
            switch row {
            case .header(let profileCount, let runningCount):
                menu.addItem(headerItem(profileCount: profileCount, runningCount: runningCount))
            case .warning(let warning):
                menu.addItem(warningItem(for: warning))
            case .profile(let entry):
                menu.addItem(profileItem(for: entry))
            case .emptyState:
                menu.addItem(emptyStateItem())
            case .command(let command):
                menu.addItem(commandItem(for: command))
            case .separator:
                menu.addItem(.separator())
            }
        }
    }

    /// Builds the menu and returns a textual rendering of it. Used by
    /// `--diagnostics`; running it also proves the menu can be constructed.
    func diagnosticsDump() -> [String] {
        rebuildMenu()

        return menu.items.map { item in
            if item.isSeparatorItem { return "  ──────────" }

            let state = item.isEnabled ? "可点" : "禁用"
            let title = (item.attributedTitle?.string ?? item.title)
                .replacingOccurrences(of: "\n", with: " / ")
            var line = "  \(title) [\(state)]"
            if let submenu = item.submenu {
                let children = submenu.items.compactMap { child -> String? in
                    guard !child.isSeparatorItem else { return nil }
                    return "\(child.title)\(child.isEnabled ? "" : "(禁用)")"
                }
                line += " ▸ " + children.joined(separator: " | ")
            }
            return line
        }
    }

    private func headerItem(profileCount: Int, runningCount: Int) -> NSMenuItem {
        let title = NSMutableAttributedString(
            string: "Chrome Profile Manager\n",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        title.append(NSAttributedString(
            string: "\(profileCount) 个配置 · \(runningCount) 个运行中",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))

        let item = NSMenuItem()
        item.attributedTitle = title
        item.isEnabled = false
        return item
    }

    private func warningItem(for warning: MenuWarning) -> NSMenuItem {
        let item = NSMenuItem(title: warning.title,
                              action: #selector(showWarning(_:)),
                              keyEquivalent: "")
        item.target = self
        item.toolTip = warning.detail
        item.attributedTitle = NSAttributedString(
            string: warning.title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.systemOrange
            ]
        )
        item.isEnabled = true
        return item
    }

    private func emptyStateItem() -> NSMenuItem {
        let item = NSMenuItem(title: "还没有配置", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.toolTip = "点击“新建配置…”创建一个空目录，Chrome 首次启动时会初始化其中的数据。"
        return item
    }

    private func commandItem(for command: MenuCommand) -> NSMenuItem {
        let item = NSMenuItem(title: command.title,
                              action: selector(for: command),
                              keyEquivalent: command.keyEquivalent)
        item.target = self
        item.isEnabled = true
        return item
    }

    private func selector(for command: MenuCommand) -> Selector {
        switch command {
        case .newProfile: return #selector(newProfile(_:))
        case .refresh: return #selector(refresh(_:))
        case .openRoot: return #selector(openRoot(_:))
        case .preferences: return #selector(showPreferences(_:))
        case .quit: return #selector(quit(_:))
        }
    }

    private func profileItem(for entry: ProfileEntry) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = attributedTitle(for: entry)
        item.representedObject = entry.profile
        item.submenu = submenu(for: entry)
        item.toolTip = entry.profile.path
        return item
    }

    private func attributedTitle(for entry: ProfileEntry) -> NSAttributedString {
        let title = NSMutableAttributedString()

        let font = NSFont.menuFont(ofSize: 0)
        let detailFont = NSFont.menuFont(ofSize: 11)

        switch entry.state {
        case .running:
            title.append(NSAttributedString(
                string: "● ",
                attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.systemGreen]
            ))
        case .unknown:
            title.append(NSAttributedString(
                string: "◌ ",
                attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.systemOrange]
            ))
        case .notRunning:
            break
        }

        title.append(NSAttributedString(string: entry.profile.name, attributes: [.font: font]))

        if entry.state.isRunning {
            title.append(NSAttributedString(
                string: "   运行中",
                attributes: [.font: detailFont, .foregroundColor: NSColor.secondaryLabelColor]
            ))
        } else if entry.state.isUnknown {
            title.append(NSAttributedString(
                string: "   状态未知",
                attributes: [.font: detailFont, .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }

        return title
    }

    private func submenu(for entry: ProfileEntry) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let open = NSMenuItem(title: entry.state.isRunning ? "已在运行" : "打开 Chrome",
                              action: #selector(openProfile(_:)),
                              keyEquivalent: "")
        open.target = self
        open.representedObject = entry.profile
        open.isEnabled = entry.canOpen
        open.toolTip = entry.canOpen
            ? "使用 \(entry.profile.path) 作为 --user-data-dir 启动 Chrome"
            : "该配置已由 Chrome 打开，请切换到对应窗口。"
        submenu.addItem(open)

        let reveal = NSMenuItem(title: "在访达中显示",
                                action: #selector(revealProfile(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = entry.profile
        submenu.addItem(reveal)

        submenu.addItem(.separator())

        let copy = NSMenuItem(title: "复制到新配置…",
                              action: #selector(copyProfile(_:)),
                              keyEquivalent: "")
        copy.target = self
        copy.representedObject = entry.profile
        copy.isEnabled = entry.canModify
        copy.toolTip = entry.canModify ? "完整复制该配置的数据到新目录" : runningHint(for: entry)
        submenu.addItem(copy)

        let trash = NSMenuItem(title: "移入废纸篓…",
                               action: #selector(trashProfile(_:)),
                               keyEquivalent: "")
        trash.target = self
        trash.representedObject = entry.profile
        trash.isEnabled = entry.canModify
        trash.toolTip = entry.canModify ? "把整个目录移到废纸篓，可在访达中恢复" : runningHint(for: entry)
        submenu.addItem(trash)

        return submenu
    }

    private func runningHint(for entry: ProfileEntry) -> String {
        if entry.state.isUnknown {
            return "无法确认该配置是否正在运行，为保护数据已禁用该操作。"
        }
        return "该配置正在被 Chrome 使用，请先退出对应的 Chrome 实例。"
    }

    // MARK: - Actions

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? Profile else { return }

        do {
            switch try service.open(profile) {
            case .launched(let pid):
                NSRunningApplication(processIdentifier: pid)?
                    .activate(options: [.activateAllWindows])
            case .alreadyRunning(let pids):
                Prompts.showInfo(
                    title: "配置已在运行",
                    message: "“\(profile.name)”已经由 Chrome 打开（\(pids.count) 个进程）。请切换到对应的 Chrome 窗口。"
                )
            }
        } catch {
            Prompts.show(error: error)
        }
    }

    @objc private func revealProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? Profile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([profile.url])
    }

    @objc private func newProfile(_ sender: Any?) {
        var initialValue = ""

        while true {
            guard let input = Prompts.askForName(
                title: "新建配置",
                message: "将在 \(displayRootPath) 下创建一个空目录。Chrome 首次启动时会自行初始化其中的数据。",
                confirmTitle: "创建",
                initialValue: initialValue
            ) else { return }

            do {
                try service.createProfile(named: input)
                rebuildMenu()
                return
            } catch {
                Prompts.show(error: error)
                guard Self.isRecoverable(error) else { return }
                initialValue = input
            }
        }
    }

    @objc private func copyProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? Profile else { return }

        // Requirement: refuse to copy while the source is in use.
        let state = service.runningState(for: profile)
        guard state.allowsDestructiveOperations else {
            Prompts.show(error: Self.inUseError(for: profile, state: state, copying: true))
            return
        }

        var initialValue = "\(profile.name) 副本"

        while true {
            guard let input = Prompts.askForName(
                title: "复制配置“\(profile.name)”",
                message: "将把整个目录完整复制到 \(displayRootPath) 下的新目录。",
                confirmTitle: "复制",
                initialValue: initialValue
            ) else { return }

            do {
                try service.copyProfile(profile, toName: input)
                rebuildMenu()
                return
            } catch {
                Prompts.show(error: error)
                guard Self.isRecoverable(error) else { return }
                initialValue = input
            }
        }
    }

    @objc private func trashProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? Profile else { return }

        let state = service.runningState(for: profile)
        guard state.allowsDestructiveOperations else {
            Prompts.show(error: Self.inUseError(for: profile, state: state, copying: false))
            return
        }

        let confirmed = Prompts.confirmDestructive(
            title: "将“\(profile.name)”移入废纸篓？",
            message: "该配置的整个目录会被移动到废纸篓，你可以稍后在访达中恢复它。此操作不会影响其他配置。",
            confirmTitle: "移入废纸篓"
        )
        guard confirmed else { return }

        do {
            try service.trashProfile(profile)
            rebuildMenu()
        } catch {
            Prompts.show(error: error)
        }
    }

    @objc private func refresh(_ sender: Any?) {
        rebuildMenu()
    }

    @objc private func openRoot(_ sender: Any?) {
        do {
            try service.store.ensureRootExists()
            NSWorkspace.shared.open(service.store.rootURL)
        } catch {
            Prompts.show(error: error)
        }
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferences: preferences,
                onRootChanged: { [weak self] in
                    self?.applyRootChange()
                }
            )
        }
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showWarning(_ sender: NSMenuItem) {
        Prompts.showInfo(
            title: sender.title,
            message: (sender.toolTip ?? "") + "\n\n" + hint(for: sender.title)
        )
    }

    @objc private func quit(_ sender: Any?) {
        // Chrome instances started from this app keep running.
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func hint(for title: String) -> String {
        if title.contains("Chrome") {
            return "请安装稳定版 Google Chrome，或把它放回“应用程序”文件夹后重试。"
        }
        if title.contains("根目录") {
            return "请在“偏好设置”中选择一个可写入的目录，或检查权限。"
        }
        return "复制和删除已被临时禁用，请稍后刷新列表重试。"
    }

    private func applyRootChange() {
        service = ProfileService(store: ProfileStore(rootURL: preferences.rootURL))
        rebuildMenu()
    }

    private var displayRootPath: String {
        (service.rootURL.path as NSString).abbreviatingWithTildeInPath
    }

    private static func isRecoverable(_ error: Error) -> Bool {
        if error is ProfileNameError { return true }
        if let storeError = error as? ProfileStoreError, case .nameConflict = storeError {
            return true
        }
        return false
    }

    private static func inUseError(for profile: Profile,
                                   state: ProfileRunningState,
                                   copying: Bool) -> Error {
        if case .unknown(let reason) = state {
            return ProfileServiceError.runningStateUnknown(reason: reason)
        }
        return copying
            ? ProfileServiceError.sourceInUse(name: profile.name)
            : ProfileServiceError.profileInUse(name: profile.name)
    }
}
