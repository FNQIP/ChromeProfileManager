import AppKit
import Foundation
import ProfileKit
import ProfileUI

/// `--diagnostics` prints the environment and the exact menu that would be
/// shown, then exits. It exists so a user can attach a readable report to a bug
/// report without opening the menu, and so the menu rendering path can be
/// exercised from a terminal.
@MainActor
enum Diagnostics {

    static func run() {
        let preferences = Preferences()
        let store = ProfileStore(rootURL: preferences.rootURL)
        let service = ProfileService(store: store)

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let controller = StatusMenuController(service: service, preferences: preferences)

        print("Chrome Profile Manager 诊断报告")
        print("版本：\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发构建")")
        print("系统：\(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("")

        print("== 配置根目录")
        print(preferences.isUsingDefaultRoot
              ? "\(preferences.rootURL.path)（默认）"
              : "\(preferences.rootURL.path)（自定义，默认目录仍为 \(Preferences.defaultRootURL.path)）")

        let snapshot = service.snapshot()
        print("配置数量：\(snapshot.entries.count)，运行中：\(snapshot.runningCount)")
        if let rootError = snapshot.rootError {
            print("根目录错误：\(rootError)")
        }
        if let listingError = snapshot.processListingError {
            print("进程列表错误：\(listingError)")
        }
        print("")

        print("== Chrome")
        if let installation = snapshot.chromeInstallation {
            print(installation.bundleURL.path)
        } else {
            print(snapshot.chromeError ?? "未找到 Chrome")
        }
        print("")

        print("== 菜单项（与打开菜单时一致）")
        for line in controller.diagnosticsDump() {
            print(line)
        }

        // 构建一次偏好设置窗口，确认布局没有异常（不显示）。
        print("")
        print("== 偏好设置窗口")
        let preferencesWindow = PreferencesWindowController(preferences: preferences,
                                                            onRootChanged: {})
        if let window = preferencesWindow.window {
            window.layoutIfNeeded()
            print("构建成功，尺寸 \(Int(window.frame.width))×\(Int(window.frame.height))")
        } else {
            print("构建失败：没有窗口")
        }

        exit(0)
    }
}
