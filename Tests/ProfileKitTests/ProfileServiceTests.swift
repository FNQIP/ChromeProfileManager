import Foundation
import Testing
@testable import ProfileKit

// MARK: - Fakes

final class FakeProcessLister: ProcessListing {
    var snapshots: [ProcessSnapshot] = []
    var error: Error?
    private(set) var callCount = 0

    func snapshot() throws -> [ProcessSnapshot] {
        callCount += 1
        if let error { throw error }
        return snapshots
    }
}

struct StubLocator: ChromeLocating {
    var result: Result<ChromeInstallation, Error>
    var searchedPaths: [String] = ["/Applications/Google Chrome.app"]

    func locate() throws -> ChromeInstallation {
        try result.get()
    }
}

final class SpyLauncher: ChromeLaunching {
    var launchedProfiles: [URL] = []
    var installedInto: [ChromeInstallation] = []
    var result: Result<Int32, Error> = .success(4242)

    func launch(profileDirectory: URL, installation: ChromeInstallation) throws -> Int32 {
        launchedProfiles.append(profileDirectory)
        installedInto.append(installation)
        return try result.get()
    }
}

// MARK: - Tests

@Suite("配置服务")
final class ProfileServiceTests {

    private let temp: TemporaryDirectory
    private let root: URL
    private let store: ProfileStore
    private let lister = FakeProcessLister()
    private let launcher = SpyLauncher()
    private let chrome: ChromeInstallation

    private let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    init() {
        temp = TemporaryDirectory()
        root = temp.url.appendingPathComponent("ChromeProfiles", isDirectory: true)
        store = ProfileStore(rootURL: root)
        chrome = ChromeInstallation(bundleURL: temp.makeDirectory("Google Chrome.app"))
    }

    deinit {
        temp.cleanup()
    }

    private func makeService(locatorError: Error? = nil) -> ProfileService {
        let locator = StubLocator(result: locatorError.map { .failure($0) } ?? .success(chrome))
        return ProfileService(store: store, locator: locator, launcher: launcher, processLister: lister)
    }

    private func runningProcess(for profile: Profile, pid: Int32 = 901) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid,
                        executablePath: chromePath,
                        arguments: [chromePath, "--user-data-dir=" + profile.path])
    }

    // MARK: Snapshot

    @Test("快照包含配置与运行状态")
    func snapshotListsProfilesWithRunningState() throws {
        let running = try store.createProfile(named: "我")
        _ = try store.createProfile(named: "姐")
        lister.snapshots = [runningProcess(for: running)]

        let snapshot = makeService().snapshot()

        #expect(snapshot.rootError == nil)
        #expect(snapshot.chromeError == nil)
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.runningCount == 1)

        let entry = try #require(snapshot.entries.first { $0.profile.name == "我" })
        #expect(entry.state.isRunning)
        #expect(!entry.canOpen)
        #expect(!entry.canModify)
    }

    @Test("快照报告缺少 Chrome")
    func snapshotReportsMissingChrome() throws {
        _ = try store.createProfile(named: "我")
        lister.snapshots = []

        let service = makeService(locatorError: ChromeLocatorError.notFound(searched: ["/Applications/Google Chrome.app"]))
        let snapshot = service.snapshot()

        #expect(!snapshot.hasChrome)
        #expect(snapshot.chromeError != nil)
    }

    @Test("进程列表读取失败时状态为未知")
    func snapshotMarksStateUnknownWhenProcessListFails() throws {
        _ = try store.createProfile(named: "我")
        lister.error = ProcessListingError.enumerationFailed(errno: 1)

        let snapshot = makeService().snapshot()

        #expect(snapshot.processListingError != nil)
        #expect(snapshot.entries.first?.state.isUnknown == true)
        #expect(snapshot.entries.first?.canModify == false)
        #expect(snapshot.entries.first?.canOpen == true)
    }

    @Test("根目录不可用时会报告错误")
    func snapshotReportsUnreadableRoot() {
        try? "x".write(to: root, atomically: true, encoding: .utf8)

        let snapshot = makeService().snapshot()
        #expect(snapshot.rootError != nil)
        #expect(snapshot.entries.isEmpty)
    }

    // MARK: Copy

    @Test("运行中的配置禁止复制")
    func copyIsBlockedWhileProfileIsRunning() throws {
        let profile = try store.createProfile(named: "我")
        lister.snapshots = [runningProcess(for: profile)]

        expectThrows(ProfileServiceError.sourceInUse(name: "我")) {
            try makeService().copyProfile(profile, toName: "我 副本")
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("我 副本").path))
    }

    @Test("运行状态未知时禁止复制")
    func copyIsBlockedWhenRunningStateIsUnknown() throws {
        let profile = try store.createProfile(named: "我")
        lister.error = ProcessListingError.enumerationFailed(errno: 1)

        let error = caughtError(ProfileServiceError.self) {
            try makeService().copyProfile(profile, toName: "我 副本")
        }
        guard case .runningStateUnknown? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("我 副本").path))
    }

    @Test("未运行时可正常复制")
    func copySucceedsWhenProfileIsNotRunning() throws {
        let profile = try store.createProfile(named: "我")
        let other = try store.createProfile(named: "姐")
        lister.snapshots = [runningProcess(for: other)]

        let copy = try makeService().copyProfile(profile, toName: "我 副本")
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    // MARK: Trash

    @Test("运行中的配置禁止删除")
    func trashIsBlockedWhileProfileIsRunning() throws {
        let profile = try store.createProfile(named: "老爸")
        lister.snapshots = [runningProcess(for: profile)]

        expectThrows(ProfileServiceError.profileInUse(name: "老爸")) {
            try makeService().trashProfile(profile)
        }
        #expect(FileManager.default.fileExists(atPath: profile.path))
    }

    @Test("未运行时可安全删除")
    func trashSucceedsWhenNotRunning() throws {
        let profile = try store.createProfile(named: "老妈")
        lister.snapshots = []

        try makeService().trashProfile(profile)
        #expect(!FileManager.default.fileExists(atPath: profile.path))
    }

    // MARK: Open

    @Test("启动时传入该配置的目录")
    func openLaunchesChromeForProfileDirectory() throws {
        let profile = try store.createProfile(named: "我（副）")
        lister.snapshots = []

        let result = try makeService().open(profile)

        #expect(result == .launched(pid: 4242))
        #expect(launcher.launchedProfiles.map(\.path) == [profile.path])
        #expect(launcher.installedInto.first == chrome)
    }

    @Test("已运行时不再重复启动")
    func openReportsAlreadyRunningWithoutLaunching() throws {
        let profile = try store.createProfile(named: "我")
        lister.snapshots = [runningProcess(for: profile)]

        let result = try makeService().open(profile)

        guard case .alreadyRunning(let pids) = result else {
            Issue.record("expected alreadyRunning, got \(result)")
            return
        }
        #expect(pids.count == 1)
        #expect(launcher.launchedProfiles.isEmpty)
    }

    @Test("Chrome 缺失时给出明确错误")
    func openFailsWhenChromeIsMissing() throws {
        let profile = try store.createProfile(named: "我")
        lister.snapshots = []

        let service = makeService(locatorError: ChromeLocatorError.notFound(searched: ["/Applications/Google Chrome.app"]))
        let error = caughtError(ProfileServiceError.self) { try service.open(profile) }

        guard case .chromeNotFound? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(launcher.launchedProfiles.isEmpty)
    }

    @Test("配置目录被外部删除时给出提示")
    func openFailsWhenProfileDirectoryDisappeared() throws {
        let profile = try store.createProfile(named: "我")
        try FileManager.default.removeItem(at: profile.url)
        lister.snapshots = []

        expectThrows(ProfileServiceError.profileMissing(name: "我")) {
            try makeService().open(profile)
        }
    }

    @Test("启动失败不会删除配置数据")
    func openPropagatesLaunchFailure() throws {
        let profile = try store.createProfile(named: "我")
        lister.snapshots = []
        launcher.result = .failure(ChromeLaunchError.launchFailed(path: chromePath, reason: "boom"))

        _ = caughtError(ChromeLaunchError.self) { try makeService().open(profile) }
        #expect(FileManager.default.fileExists(atPath: profile.path))
    }
}

@Suite("偏好设置")
final class PreferencesTests {

    private let defaults: UserDefaults
    private let suiteName: String
    private let temp: TemporaryDirectory

    init() {
        suiteName = "cpm-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        temp = TemporaryDirectory()
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        temp.cleanup()
    }

    @Test("默认根目录为 ~/ChromeProfiles")
    func defaultRootIsChromeProfilesInHome() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.isUsingDefaultRoot)
        #expect(preferences.rootURL.path == PathHelpers.canonicalPath("~/ChromeProfiles"))
    }

    @Test("自定义根目录会被持久化")
    func settingCustomRootPersists() throws {
        let preferences = Preferences(defaults: defaults)
        let custom = temp.url.appendingPathComponent("CustomRoot", isDirectory: true)

        try preferences.setRootURL(custom)

        #expect(!preferences.isUsingDefaultRoot)
        #expect(preferences.rootURL.path == custom.standardizedFileURL.path)
        #expect(Preferences(defaults: defaults).rootURL.path == custom.standardizedFileURL.path)
    }

    @Test("指向普通文件时拒绝设置")
    func settingRootOnAFileIsRejected() {
        let preferences = Preferences(defaults: defaults)
        let file = temp.writeFile("occupied")

        let error = caughtError(ProfileStoreError.self) { try preferences.setRootURL(file) }
        guard case .rootIsNotDirectory? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test("恢复默认会清除自定义根目录")
    func resetRestoresDefaultRoot() throws {
        let preferences = Preferences(defaults: defaults)
        try preferences.setRootURL(temp.url.appendingPathComponent("Custom", isDirectory: true))
        preferences.resetRoot()

        #expect(preferences.isUsingDefaultRoot)
        #expect(preferences.rootURL.path == PathHelpers.canonicalPath("~/ChromeProfiles"))
    }
}
