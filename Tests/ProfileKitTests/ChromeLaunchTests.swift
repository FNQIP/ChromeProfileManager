import Foundation
import Testing
@testable import ProfileKit

@Suite("Chrome 启动参数")
struct ChromeLaunchArgumentTests {

    private let root = URL(fileURLWithPath: "/Users/test/ChromeProfiles", isDirectory: true)

    @Test("只包含 user-data-dir 与 new-window 两个参数")
    func argumentsUseSingleUserDataDirElement() {
        let arguments = ChromeLaunchArguments.make(for: root.appendingPathComponent("我", isDirectory: true))

        #expect(arguments.count == 2)
        #expect(arguments[0] == "--user-data-dir=/Users/test/ChromeProfiles/我")
        #expect(arguments[1] == "--new-window")
    }

    @Test("中文、空格与特殊字符始终位于同一个参数")
    func cjkSpaceAndSpecialCharactersStayInOneElement() {
        let names = [
            "我（副）",
            "Work Profile",
            "a & b; rm -rf *",
            "quote's \"double\"",
            "日本語 プロファイル",
            "100% 完成 #1"
        ]

        for name in names {
            let url = root.appendingPathComponent(name, isDirectory: true)
            let arguments = ChromeLaunchArguments.make(for: url)

            #expect(arguments.count == 2)
            #expect(arguments[0] == "--user-data-dir=" + url.standardizedFileURL.path)
            #expect(arguments[0].hasSuffix(name))
            #expect(arguments[1] == "--new-window")
        }
    }

    @Test("末尾斜杠被规范化")
    func trailingSlashIsNormalised() {
        let withSlash = URL(fileURLWithPath: "/Users/test/ChromeProfiles/工作/", isDirectory: true)
        let arguments = ChromeLaunchArguments.make(for: withSlash)
        #expect(arguments[0] == "--user-data-dir=/Users/test/ChromeProfiles/工作")
    }

    @Test("不会拼出一整段命令字符串")
    func argumentsNeverContainAConsolidatedCommandString() {
        let url = URL(fileURLWithPath: "/tmp/Chrome Profiles/我的 配置; echo hacked", isDirectory: true)
        let arguments = ChromeLaunchArguments.make(for: url)

        #expect(arguments.count == 2)
        #expect(!arguments[0].hasPrefix("open "))
        #expect(!arguments[0].contains("&&"))
    }
}

@Suite("Chrome 定位")
final class ChromeLocatorTests {

    private let temp: TemporaryDirectory

    init() {
        temp = TemporaryDirectory()
    }

    deinit {
        temp.cleanup()
    }

    @Test("未安装时给出所检查的位置")
    func missingChromeIsReportedWithSearchedPaths() {
        let locator = ChromeLocator(candidatePaths: ["/nonexistent/Google Chrome.app"])

        let error = caughtError(ChromeLocatorError.self) { try locator.locate() }
        guard case .notFound(let searched)? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(searched == ["/nonexistent/Google Chrome.app"])
    }

    @Test("能在模拟的 Bundle 中找到 Chrome")
    func findsChromeInsideFakeBundle() throws {
        let bundle = temp.makeDirectory("Google Chrome.app/Contents/MacOS")
        let executable = bundle.appendingPathComponent("Google Chrome")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let locator = ChromeLocator(candidatePaths: [temp.url.appendingPathComponent("Google Chrome.app").path])
        let installation = try locator.locate()

        #expect(installation.executableURL.path == executable.path)
        #expect(installation.bundleURL.lastPathComponent == "Google Chrome.app")
    }

    @Test("Bundle 缺少可执行文件时报错")
    func bundleWithoutExecutableIsReported() {
        temp.makeDirectory("Google Chrome.app/Contents/MacOS")
        let locator = ChromeLocator(candidatePaths: [temp.url.appendingPathComponent("Google Chrome.app").path])

        let error = caughtError(ChromeLocatorError.self) { try locator.locate() }
        guard case .executableMissing? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }
}
