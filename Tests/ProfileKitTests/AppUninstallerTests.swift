import Foundation
import Testing
@testable import ProfileKit

@Suite("卸载")
final class AppUninstallerTests {

    private let temp: TemporaryDirectory
    private let uninstaller: AppUninstaller

    init() {
        temp = TemporaryDirectory()
        uninstaller = AppUninstaller()
    }

    deinit {
        temp.cleanup()
    }

    /// 造一个假的 .app 目录，避免测试动到真实应用。
    private func makeFakeApp(_ name: String = "ChromeProfiles.app",
                             under parent: URL? = nil) -> URL {
        let base = parent ?? temp.url
        let app = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS",
                                                                                isDirectory: true),
                                                 withIntermediateDirectories: true)
        return app
    }

    @Test("非 .app 目标会被拒绝")
    func rejectsNonApplication() {
        let folder = temp.makeDirectory("NotAnApp")

        let error = caughtError(UninstallError.self) {
            try uninstaller.validateApplication(at: folder)
        }
        guard case .notAnApplication? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test("缺失的应用包会被拒绝")
    func rejectsMissingBundle() {
        let ghost = temp.url.appendingPathComponent("Ghost.app", isDirectory: true)

        let error = caughtError(UninstallError.self) {
            try uninstaller.validateApplication(at: ghost)
        }
        guard case .notAnApplication? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test("正常运行位置的应用可以通过校验")
    func acceptsApplicationInWritableFolder() throws {
        let app = makeFakeApp()
        try uninstaller.validateApplication(at: app)
    }

    @Test("只读目录里的应用会被拒绝")
    func rejectsApplicationInReadOnlyFolder() {
        let readonly = temp.makeDirectory("ReadOnly")
        let app = makeFakeApp(under: readonly)
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readonly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readonly.path)
        }

        let error = caughtError(UninstallError.self) {
            try uninstaller.validateApplication(at: app)
        }
        guard case .readOnlyLocation? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test("App Translocation 路径会被拒绝")
    func rejectsTranslocatedApplication() {
        // 模拟从 DMG 直接运行时系统挂载的只读路径。
        let translocation = temp.makeDirectory("AppTranslocation/session-1/d")
        let app = makeFakeApp(under: translocation)

        let error = caughtError(UninstallError.self) {
            try uninstaller.validateApplication(at: app)
        }
        guard case .readOnlyLocation? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test("卸载会把应用移入废纸篓")
    func movesApplicationToTrash() throws {
        let app = makeFakeApp()
        #expect(FileManager.default.fileExists(atPath: app.path))

        _ = try uninstaller.moveToTrash(app)

        #expect(!FileManager.default.fileExists(atPath: app.path))
        // 同一目录下的其他内容不受影响。
        #expect(FileManager.default.fileExists(atPath: temp.url.path))
    }

    @Test("卸载不会碰配置根目录")
    func doesNotTouchProfileRoot() throws {
        let profilesRoot = temp.makeDirectory("ChromeProfiles/我")
        let app = makeFakeApp()

        _ = try uninstaller.moveToTrash(app)

        #expect(FileManager.default.fileExists(atPath: profilesRoot.path))
    }

    @Test("清除偏好设置只影响本应用的域")
    func clearsOnlyOwnPreferences() throws {
        let suiteName = "cpm-uninstall-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("/tmp/somewhere", forKey: "ProfileRootPath")
        #expect(defaults.string(forKey: "ProfileRootPath") != nil)

        uninstaller.clearPreferences(domain: suiteName, defaults: defaults)

        #expect(defaults.string(forKey: "ProfileRootPath") == nil)
    }
}
