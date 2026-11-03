import Foundation
import Testing
@testable import ProfileKit
@testable import ProfileUI

@Suite("菜单结构")
struct MenuModelTests {

    private let root = URL(fileURLWithPath: "/Users/me/ChromeProfiles", isDirectory: true)

    private func entry(_ name: String, state: ProfileRunningState = .notRunning) -> ProfileEntry {
        ProfileEntry(
            profile: Profile(name: name, url: root.appendingPathComponent(name, isDirectory: true)),
            state: state
        )
    }

    private func snapshot(entries: [ProfileEntry] = [],
                          chrome: Bool = true,
                          rootError: String? = nil,
                          chromeError: String? = nil,
                          processListingError: String? = nil) -> MenuSnapshot {
        MenuSnapshot(
            rootURL: root,
            entries: entries,
            chromeInstallation: chrome
                ? ChromeInstallation(bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
                : nil,
            rootError: rootError,
            chromeError: chromeError ?? (chrome ? nil : "未找到 Chrome"),
            processListingError: processListingError
        )
    }

    @Test("空列表显示空状态与新建入口")
    func emptyListShowsEmptyStateAndCreateCommand() {
        let model = MenuModel.make(from: snapshot())

        #expect(model.rows.first == .header(profileCount: 0, runningCount: 0))
        #expect(model.rows.contains(.emptyState))
        #expect(model.rows.contains(.command(.newProfile)))
        #expect(model.warnings.isEmpty)
    }

    @Test("有配置时按名称顺序列出且不显示空状态")
    func profilesAreListedInOrder() {
        let model = MenuModel.make(from: snapshot(entries: [
            entry("Alpha"),
            entry("我"),
            entry("我（副）")
        ]))

        #expect(model.profileEntries.map(\.profile.name) == ["Alpha", "我", "我（副）"])
        #expect(!model.rows.contains(.emptyState))
    }

    @Test("运行中的配置禁止打开、复制与删除")
    func runningProfileDisablesUnsafeActions() {
        let model = MenuModel.make(from: snapshot(entries: [
            entry("我", state: .running(pids: [12])),
            entry("姐")
        ]))

        let running = model.profileEntries[0]
        #expect(!running.canOpen)
        #expect(!running.canModify)

        let idle = model.profileEntries[1]
        #expect(idle.canOpen)
        #expect(idle.canModify)
    }

    @Test("状态未知时保守禁用复制与删除")
    func unknownStateDisablesDestructiveActions() {
        let model = MenuModel.make(from: snapshot(entries: [
            entry("我", state: .unknown(reason: "无法读取进程列表"))
        ]))

        #expect(model.profileEntries[0].canModify == false)
        #expect(model.profileEntries[0].state.isUnknown)
    }

    @Test("统计运行中的数量")
    func headerCountsRunningProfiles() {
        let model = MenuModel.make(from: snapshot(entries: [
            entry("我", state: .running(pids: [1])),
            entry("姐"),
            entry("老妈", state: .running(pids: [2, 3]))
        ]))

        guard case .header(let count, let running) = model.rows.first else {
            Issue.record("first row must be a header")
            return
        }
        #expect(count == 3)
        #expect(running == 2)
    }

    @Test("未安装 Chrome 时给出警告")
    func missingChromeAddsWarning() {
        let model = MenuModel.make(from: snapshot(entries: [entry("我")], chrome: false))
        #expect(model.warnings.count == 1)
        if case .chromeMissing = model.warnings[0] {} else {
            Issue.record("expected chromeMissing warning")
        }
    }

    @Test("根目录不可用时不显示空状态")
    func rootErrorSuppressesEmptyState() {
        let model = MenuModel.make(from: snapshot(rootError: "无法访问配置根目录"))

        #expect(model.warnings.count == 1)
        #expect(!model.rows.contains(.emptyState))
        #expect(model.rows.contains(.command(.newProfile)))
    }

    @Test("进程列表不可读时提示并降级")
    func processListingFailureAddsWarning() {
        let model = MenuModel.make(from: snapshot(entries: [entry("我", state: .unknown(reason: "x"))],
                                                  processListingError: "无法读取系统进程列表"))

        #expect(model.warnings.count == 1)
        if case .processListingUnavailable = model.warnings[0] {} else {
            Issue.record("expected processListingUnavailable warning")
        }
        #expect(model.profileEntries[0].canModify == false)
    }

    @Test("警告顺序固定：根目录、Chrome、进程列表")
    func warningOrderIsStable() {
        let model = MenuModel.make(from: snapshot(chrome: false,
                                                  rootError: "root",
                                                  chromeError: "chrome",
                                                  processListingError: "ps"))

        #expect(model.warnings.count == 3)
        if case .rootUnavailable = model.warnings[0] {} else { Issue.record("1st should be root") }
        if case .chromeMissing = model.warnings[1] {} else { Issue.record("2nd should be chrome") }
        if case .processListingUnavailable = model.warnings[2] {} else { Issue.record("3rd should be ps") }
    }

    @Test("命令顺序与快捷键固定")
    func commandsAreOrdered() {
        let model = MenuModel.make(from: snapshot())
        let commands = model.rows.compactMap { row -> MenuCommand? in
            if case .command(let command) = row { return command }
            return nil
        }

        #expect(commands == [.newProfile, .refresh, .openRoot, .preferences, .quit])
        #expect(MenuCommand.newProfile.keyEquivalent == "n")
        #expect(MenuCommand.refresh.keyEquivalent == "r")
        #expect(MenuCommand.preferences.keyEquivalent == ",")
        #expect(MenuCommand.quit.keyEquivalent == "q")
        #expect(MenuCommand.openRoot.keyEquivalent.isEmpty)
    }

    @Test("列表以分隔线结束命令区")
    func layoutHasSeparators() {
        let model = MenuModel.make(from: snapshot(entries: [entry("我")]))

        guard let profileIndex = model.rows.firstIndex(of: .profile(entry("我"))),
              let firstSeparator = model.rows.firstIndex(of: .separator),
              let lastSeparator = model.rows.lastIndex(of: .separator) else {
            Issue.record("expected separators around the command area")
            return
        }

        #expect(firstSeparator < profileIndex)
        #expect(lastSeparator > profileIndex)
        #expect(model.rows.last == .command(.quit))
    }
}
