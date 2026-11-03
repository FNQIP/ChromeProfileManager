import Foundation
import Testing
@testable import ProfileKit

@Suite("进程命令行解析")
struct ProcessCommandLineParserTests {

    /// Builds a buffer shaped like `sysctl(KERN_PROCARGS2)`.
    private func buffer(argc: Int32, path: String, arguments: [String], padding: Int = 2) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(UInt8(truncatingIfNeeded: argc))
        bytes.append(UInt8(truncatingIfNeeded: argc >> 8))
        bytes.append(UInt8(truncatingIfNeeded: argc >> 16))
        bytes.append(UInt8(truncatingIfNeeded: argc >> 24))
        bytes.append(contentsOf: Array(path.utf8))
        bytes.append(0)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: padding))
        for argument in arguments {
            bytes.append(contentsOf: Array(argument.utf8))
            bytes.append(0)
        }
        return bytes
    }

    @Test("解析中文参数")
    func parsesChineseArguments() throws {
        let arguments = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "--user-data-dir=/Users/me/ChromeProfiles/我（副）",
            "--new-window"
        ]
        let raw = buffer(argc: 3,
                         path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                         arguments: arguments)

        let parsed = try #require(ProcessCommandLineParser.parse(raw))
        #expect(parsed.executablePath == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        #expect(parsed.arguments == arguments)
    }

    @Test("解析含空格的路径")
    func parsesPathsContainingSpaces() throws {
        let arguments = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "--user-data-dir=/Users/me/Chrome Profiles/Work Profile"
        ]
        let raw = buffer(argc: 2,
                         path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                         arguments: arguments)

        let parsed = try #require(ProcessCommandLineParser.parse(raw))
        #expect(ChromeUsageDetector.userDataDirValue(in: parsed.arguments) == "/Users/me/Chrome Profiles/Work Profile")
    }

    @Test("只读取声明数量的参数，忽略后续环境变量")
    func stopsAfterDeclaredArgumentCount() throws {
        var raw = buffer(argc: 2,
                         path: "/bin/chrome",
                         arguments: ["/bin/chrome", "--user-data-dir=/tmp/a"])
        raw.append(contentsOf: Array("PATH=/usr/bin".utf8))
        raw.append(0)

        let parsed = try #require(ProcessCommandLineParser.parse(raw))
        #expect(parsed.arguments.count == 2)
        #expect(!parsed.arguments.contains("PATH=/usr/bin"))
    }

    @Test("拒绝被截断的缓冲区")
    func rejectsTruncatedBuffer() {
        #expect(ProcessCommandLineParser.parse([0x01]) == nil)
        #expect(ProcessCommandLineParser.parse([]) == nil)
    }
}

@Suite("运行状态匹配")
struct ChromeUsageDetectorTests {

    private let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let root = "/Users/me/ChromeProfiles"

    private func chromeProcess(pid: Int32, userDataDir: String?) -> ProcessSnapshot {
        var arguments = [chromePath]
        if let userDataDir {
            arguments.append("--user-data-dir=" + userDataDir)
        }
        return ProcessSnapshot(pid: pid, executablePath: chromePath, arguments: arguments)
    }

    @Test("匹配完全一致的配置")
    func matchesExactProfile() {
        let processes = [chromeProcess(pid: 100, userDataDir: root + "/我")]
        let pids = ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/我"),
            in: processes
        )
        #expect(pids == [100])
    }

    @Test("不会把名称相近的配置混淆")
    func doesNotConfuseSimilarNames() {
        let processes = [
            chromeProcess(pid: 100, userDataDir: root + "/我（副）"),
            chromeProcess(pid: 101, userDataDir: root + "/我"),
            chromeProcess(pid: 102, userDataDir: root + "/老爸")
        ]

        #expect(ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/我"), in: processes
        ) == [101])

        #expect(ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/姐"), in: processes
        ).isEmpty)
    }

    @Test("忽略末尾斜杠与冗余路径成分")
    func matchesDespiteTrailingSlashAndRedundantComponents() {
        let processes = [chromeProcess(pid: 7, userDataDir: root + "/工作/")]
        let pids = ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/./工作", isDirectory: true),
            in: processes
        )
        #expect(pids == [7])
    }

    @Test("忽略使用默认目录的 Chrome")
    func ignoresChromeUsingItsDefaultProfile() {
        let processes = [ProcessSnapshot(pid: 5, executablePath: chromePath, arguments: [chromePath])]
        #expect(ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/我"), in: processes
        ).isEmpty)
    }

    @Test("忽略携带同名参数的非 Chrome 进程")
    func ignoresNonChromeProcessesCarryingTheFlag() {
        let processes = [
            ProcessSnapshot(pid: 9,
                            executablePath: "/usr/bin/some-tool",
                            arguments: ["some-tool", "--user-data-dir=" + root + "/我"])
        ]
        #expect(ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/我"), in: processes
        ).isEmpty)
    }

    @Test("识别 Chrome 辅助进程")
    func recognisesChromeHelperProcesses() {
        let helper = ProcessSnapshot(
            pid: 11,
            executablePath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper",
            arguments: ["Google Chrome Helper", "--user-data-dir=" + root + "/老妈"]
        )
        #expect(ChromeUsageDetector.isChromeProcess(helper))
        #expect(ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/老妈"), in: [helper]
        ) == [11])
    }

    @Test("支持参数与值分开写的形式")
    func supportsSeparateFlagAndValue() {
        let process = ProcessSnapshot(pid: 12,
                                      executablePath: chromePath,
                                      arguments: [chromePath, "--user-data-dir", root + "/姐"])
        #expect(ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/姐"), in: [process]
        ) == [12])
    }

    @Test("同一配置的多个进程都会报告")
    func multipleProcessesOfOneProfileAreAllReported() {
        let processes = [
            chromeProcess(pid: 20, userDataDir: root + "/老爸"),
            ProcessSnapshot(pid: 21,
                            executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper (Renderer)",
                            arguments: ["helper", "--user-data-dir=" + root + "/老爸"])
        ]
        #expect(ChromeUsageDetector.pidsUsing(
            userDataDirectory: URL(fileURLWithPath: root + "/老爸"), in: processes
        ) == [20, 21])
    }

    @Test("没有匹配时视为未运行")
    func stateIsNotRunningWhenNothingMatches() {
        let profile = Profile(name: "我", url: URL(fileURLWithPath: root + "/我", isDirectory: true))
        #expect(ChromeUsageDetector.state(for: profile, in: []) == .notRunning)
    }

    @Test("有匹配时视为运行中")
    func stateIsRunningWhenMatched() {
        let profile = Profile(name: "我", url: URL(fileURLWithPath: root + "/我", isDirectory: true))
        let processes = [chromeProcess(pid: 42, userDataDir: root + "/我")]
        #expect(ChromeUsageDetector.state(for: profile, in: processes) == .running(pids: [42]))
    }
}

@Suite("路径处理")
struct PathHelpersTests {

    @Test("去掉末尾斜杠")
    func trailingSlashIsRemoved() {
        #expect(PathHelpers.canonicalPath("/tmp/a/b/") == "/tmp/a/b")
    }

    @Test("展开波浪号")
    func tildeIsExpanded() {
        let expanded = PathHelpers.canonicalPath("~/ChromeProfiles")
        #expect(!expanded.hasPrefix("~"))
        #expect(expanded.hasSuffix("/ChromeProfiles"))
    }

    @Test("判断直接子目录")
    func directChildRelationship() {
        #expect(PathHelpers.isDirectChild("/a/b/c", of: "/a/b"))
        #expect(!PathHelpers.isDirectChild("/a/b/c/d", of: "/a/b"))
        #expect(!PathHelpers.isDirectChild("/a/b", of: "/a/b"))
        #expect(!PathHelpers.isDirectChild("/a/bb/c", of: "/a/b"))
    }

    @Test("路径等价判断忽略冗余成分")
    func sameLocationIgnoresRedundantComponents() {
        #expect(PathHelpers.pathsReferToSameLocation("/a/b/./c", "/a/b/c"))
        #expect(!PathHelpers.pathsReferToSameLocation("/a/b/c", "/a/b/cc"))
    }
}
