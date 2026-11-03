//
// 本地验收程序（不随应用分发）
//
// 使用真实的 Chrome 二进制和一个临时配置根目录，验证：
//   - 目录扫描、创建、复制、移入废纸篓
//   - 通过 sysctl 读取真实 argv 并匹配 --user-data-dir
//   - 多个配置可以分别启动且互不干扰
//
// 安全性：只操作临时目录；只会结束本程序自己启动的 headless Chrome 进程，
// 不会影响用户正在使用的 Chrome 实例与 ~/ChromeProfiles 中的数据。
//
// 运行：swift run -c release --disable-sandbox IntegrationCheck
//
import Darwin
import Foundation
import ProfileKit

var failures = 0
var checks = 0

func check(_ condition: Bool, _ label: String) {
    checks += 1
    if condition {
        print("  ✅ \(label)")
    } else {
        failures += 1
        print("  ❌ \(label)")
    }
}

func section(_ title: String) {
    print("\n== \(title)")
}

func note(_ text: String) {
    print("  · \(text)")
}

let fileManager = FileManager.default
let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("CPMIntegration-\(UUID().uuidString)", isDirectory: true)

let store = ProfileStore(rootURL: tempRoot)
let lister = SystemProcessLister()
let service = ProfileService(store: store, processLister: lister)

var spawnedPIDs: [pid_t] = []

print("Chrome Profiles 本地验收")
print("临时根目录：\(tempRoot.path)")

// MARK: - 1. 目录管理

section("1. 目录管理")
do {
    try store.ensureRootExists()
    check(fileManager.fileExists(atPath: tempRoot.path), "根目录已创建")

    let first = try store.createProfile(named: "我")
    let second = try store.createProfile(named: "Work Profile 测试")
    check(try store.listProfiles().count == 2, "扫描到两个配置")
    check(try store.listProfiles().map(\.name).contains("Work Profile 测试"), "含空格的名称可以创建")
    check(first.path != second.path, "两个配置的路径不同")

    try "marker".write(to: first.url.appendingPathComponent("Cookies"),
                       atomically: true, encoding: .utf8)
    let copy = try store.copyProfile(first, to: "我（副）")
    check(fileManager.fileExists(atPath: copy.url.appendingPathComponent("Cookies").path),
          "复制包含数据文件")
    check(try store.listProfiles().count == 3, "复制后列表为三项")

    try store.trashProfile(copy)
    check(!fileManager.fileExists(atPath: copy.path), "删除后目录离开根目录")
    check(try store.listProfiles().count == 2, "删除后列表恢复两项")

    // 清掉复制测试留下的文件，让第 3 步从空目录开始。
    try? fileManager.removeItem(at: first.url.appendingPathComponent("Cookies"))
} catch {
    print("  ❌ 目录测试失败：\(error.localizedDescription)")
    failures += 1
}

// MARK: - 2. Chrome

section("2. Chrome 安装检查")
var installation: ChromeInstallation?
do {
    let located = try ChromeLocator().locate()
    installation = located
    note("Chrome：\(located.bundleURL.path)")
    check(fileManager.isExecutableFile(atPath: located.executableURL.path), "Chrome 可执行文件存在")
} catch {
    print("  ❌ 找不到 Chrome：\(error.localizedDescription)")
}

// MARK: - 3. 真实启动

section("3. 空目录启动与运行状态识别（真实 Chrome，headless）")
if let installation {
    do {
        let profiles = try store.listProfiles()
        guard let alpha = profiles.first(where: { $0.name == "我" }),
              let beta = profiles.first(where: { $0.name == "Work Profile 测试" }) else {
            throw IntegrationCheckError.missingProfile
        }

        check(try fileManager.contentsOfDirectory(atPath: alpha.path).isEmpty,
              "启动前配置目录为空（由 Chrome 初始化）")

        let alphaPID = try launchHeadless(alpha, using: installation)
        spawnedPIDs.append(alphaPID)

        let alphaDetected = waitUntil(timeout: 25) { !detectedPIDs(for: alpha).isEmpty }
        check(alphaDetected, "Chrome 启动后能识别该配置正在运行")

        if alphaDetected {
            note("检测到的进程：\(detectedPIDs(for: alpha))")
            check(detectedPIDs(for: beta).isEmpty, "不会把另一个配置误判为运行中")
            let initialized = waitUntil(timeout: 20) {
                fileManager.fileExists(atPath: alpha.url.appendingPathComponent("Local State").path)
                    || fileManager.fileExists(atPath: alpha.url.appendingPathComponent("Default").path)
            }
            check(initialized, "Chrome 已自行初始化用户数据")
            if !initialized {
                note("目录内容：\((try? fileManager.contentsOfDirectory(atPath: alpha.path)) ?? [])")
            }

            var copyBlocked = false
            do { _ = try service.copyProfile(alpha, toName: "我 运行中副本") } catch { copyBlocked = true }
            check(copyBlocked, "运行中的配置禁止复制")

            var trashBlocked = false
            do { try service.trashProfile(alpha) } catch { trashBlocked = true }
            check(trashBlocked, "运行中的配置禁止删除")
            check(fileManager.fileExists(atPath: alpha.path), "禁止删除后目录仍然存在")
        }

        let betaPID = try launchHeadless(beta, using: installation)
        spawnedPIDs.append(betaPID)

        let bothDetected = waitUntil(timeout: 25) {
            !detectedPIDs(for: alpha).isEmpty && !detectedPIDs(for: beta).isEmpty
        }
        check(bothDetected, "两个配置可以分别启动")

        if bothDetected {
            let alphaPIDs = Set(detectedPIDs(for: alpha))
            let betaPIDs = Set(detectedPIDs(for: beta))
            check(alphaPIDs.isDisjoint(with: betaPIDs), "两个配置的进程不重叠")

            if let snapshot = try? lister.snapshot(),
               let betaProcess = snapshot.first(where: { uses(profile: beta, process: $0) }) {
                check(betaProcess.arguments.contains { $0 == "--user-data-dir=" + beta.path },
                      "argv 中的 --user-data-dir 与含空格/中文的目录路径完全一致")
            }
        }
    } catch {
        print("  ❌ 启动测试失败：\(error.localizedDescription)")
        failures += 1
    }
} else {
    print("  ⚠︎ 跳过：未安装 Chrome")
}

// MARK: - 4. 退出与清理

section("4. 退出后的状态")
for pid in spawnedPIDs {
    kill(pid, SIGTERM)
}
let stopped = waitUntil(timeout: 30) { !anyTestChromeRunning() }
check(stopped, "测试用的 Chrome 实例已退出，且不影响其他 Chrome")

if stopped, let profiles = try? store.listProfiles(),
   let alpha = profiles.first(where: { $0.name == "我" }) {
    let snapshot = (try? lister.snapshot()) ?? []
    check(ChromeUsageDetector.state(for: alpha, in: snapshot) == .notRunning, "退出后状态回到未运行")

    var copied = false
    if let copy = try? store.copyProfile(alpha, to: "我 副本2") {
        copied = true
        try? store.trashProfile(copy)
    }
    check(copied, "退出后可以复制配置")
}

// MARK: - 5. 真实根目录（只读）

section("5. 真实配置根目录（只读）")
let realRoot = Preferences.defaultRootURL
if fileManager.fileExists(atPath: realRoot.path) {
    let realStore = ProfileStore(rootURL: realRoot)
    if let profiles = try? realStore.listProfiles() {
        note("\(realRoot.path)：\(profiles.count) 个配置（未做任何修改）")
        for profile in profiles.prefix(8) {
            note("  - \(profile.name)")
        }
    }
} else {
    note("\(realRoot.path) 尚不存在")
}

// MARK: - 结束

try? fileManager.removeItem(at: tempRoot)

print("\n结果：\(checks - failures)/\(checks) 项通过")

// MARK: - Helpers

enum IntegrationCheckError: LocalizedError {
    case missingProfile

    var errorDescription: String? {
        "缺少测试所需的配置目录"
    }
}

func testArguments(for profile: Profile) -> [String] {
    // 与 ChromeLaunchArguments.make 使用相同的 user-data-dir 形式，去掉
    // --new-window 并附加 headless 参数，以免在桌面上弹出窗口。
    var arguments = ChromeLaunchArguments.make(for: profile.url)
    arguments.removeAll { $0 == ChromeLaunchArguments.newWindowFlag }
    arguments.append(contentsOf: [
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions"
    ])
    return arguments
}

func launchHeadless(_ profile: Profile, using installation: ChromeInstallation) throws -> Int32 {
    let process = Process()
    process.executableURL = installation.executableURL
    process.arguments = testArguments(for: profile)
    try process.run()
    return process.processIdentifier
}

func waitUntil(timeout: TimeInterval, _ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        usleep(200_000)
    }
    return predicate()
}

func detectedPIDs(for profile: Profile) -> [Int32] {
    guard let snapshot = try? lister.snapshot() else { return [] }
    return ChromeUsageDetector.pidsUsing(userDataDirectory: profile.url, in: snapshot)
}

func uses(profile: Profile, process: ProcessSnapshot) -> Bool {
    guard let value = ChromeUsageDetector.userDataDirValue(in: process.arguments) else { return false }
    return PathHelpers.pathsReferToSameLocation(PathHelpers.canonicalPath(value),
                                                PathHelpers.canonicalPath(for: profile.url))
}

func anyTestChromeRunning() -> Bool {
    guard let snapshot = try? lister.snapshot() else { return true }
    let prefix = PathHelpers.canonicalPath(tempRoot.path)

    return snapshot.contains { process in
        guard let value = ChromeUsageDetector.userDataDirValue(in: process.arguments) else { return false }
        let path = PathHelpers.canonicalPath(value)
        return path == prefix || path.hasPrefix(prefix + "/")
    }
}

exit(failures == 0 ? 0 : 1)
