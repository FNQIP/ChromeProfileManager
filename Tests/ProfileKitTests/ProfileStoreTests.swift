import Foundation
import Testing
@testable import ProfileKit

@Suite("配置目录")
final class ProfileStoreTests {

    private let temp: TemporaryDirectory
    private let root: URL
    private let store: ProfileStore

    init() {
        temp = TemporaryDirectory()
        root = temp.url.appendingPathComponent("ChromeProfiles", isDirectory: true)
        store = ProfileStore(rootURL: root)
    }

    deinit {
        temp.cleanup()
    }

    // MARK: - Root

    @Test("根目录不存在时自动创建")
    func rootIsCreatedWhenMissing() throws {
        #expect(!FileManager.default.fileExists(atPath: root.path))
        try store.ensureRootExists()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("根目录被普通文件占用时报错")
    func rootThatIsAFileIsRejected() throws {
        try "not a directory".write(to: root, atomically: true, encoding: .utf8)

        let error = caughtError(ProfileStoreError.self) { try store.ensureRootExists() }
        guard case .rootIsNotDirectory? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    // MARK: - Listing

    @Test("只列出一级目录")
    func listingIncludesOnlyFirstLevelDirectories() throws {
        try store.ensureRootExists()

        let fm = FileManager.default
        for name in ["我", "我（副）", "Alpha"] {
            try fm.createDirectory(at: root.appendingPathComponent(name, isDirectory: true),
                                   withIntermediateDirectories: false)
        }
        try "x".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: root.appendingPathComponent(".hidden", isDirectory: true),
                               withIntermediateDirectories: false)
        try fm.createDirectory(at: root.appendingPathComponent("Alpha/Default", isDirectory: true),
                               withIntermediateDirectories: true)

        let names = try store.listProfiles().map(\.name)
        #expect(names.count == 3)
        #expect(Set(names) == ["我", "我（副）", "Alpha"])
        #expect(!names.contains(".hidden"))
        #expect(!names.contains("notes.txt"))
        #expect(!names.contains("Default"))
    }

    @Test("按名称排序")
    func listingIsSorted() throws {
        try store.ensureRootExists()
        for name in ["Charlie", "Alpha", "Bravo"] {
            try store.createProfile(named: name)
        }
        #expect(try store.listProfiles().map(\.name) == ["Alpha", "Bravo", "Charlie"])
    }

    @Test("空根目录没有配置")
    func emptyRootListsNothing() throws {
        try store.ensureRootExists()
        #expect(try store.listProfiles().isEmpty)
    }

    @Test("忽略符号链接目录")
    func symlinkedDirectoryIsIgnored() throws {
        try store.ensureRootExists()
        let target = temp.makeDirectory("Elsewhere")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"),
            withDestinationURL: target
        )
        #expect(try store.listProfiles().isEmpty)
    }

    // MARK: - Create

    @Test("新建配置只创建空目录")
    func createMakesEmptyDirectory() throws {
        let profile = try store.createProfile(named: " 老妈 ")

        #expect(profile.name == "老妈")
        #expect(FileManager.default.fileExists(atPath: profile.path))
        let contents = try FileManager.default.contentsOfDirectory(atPath: profile.path)
        #expect(contents.isEmpty, "新目录必须保持为空，由 Chrome 首次启动时初始化")
    }

    @Test("重名时拒绝创建且不覆盖")
    func createRejectsDuplicateName() throws {
        try store.createProfile(named: "姐")

        expectThrows(ProfileStoreError.nameConflict(name: "姐")) {
            try store.createProfile(named: "姐")
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("姐").path))
    }

    @Test("非法名称不写入磁盘")
    func createRejectsInvalidNameWithoutTouchingDisk() throws {
        expectThrows(ProfileNameError.pathTraversal) { try store.createProfile(named: "../escape") }
        expectThrows(ProfileNameError.containsPathSeparator) { try store.createProfile(named: "a/b") }

        let escaped = temp.url.appendingPathComponent("escape")
        #expect(!FileManager.default.fileExists(atPath: escaped.path))
    }

    @Test("同名文件已存在时拒绝创建")
    func createRejectsExistingFileWithSameName() throws {
        try store.ensureRootExists()
        try "x".write(to: root.appendingPathComponent("collision"), atomically: true, encoding: .utf8)

        expectThrows(ProfileStoreError.nameConflict(name: "collision")) {
            try store.createProfile(named: "collision")
        }
    }

    // MARK: - Copy

    @Test("复制会完整复制目录内容")
    func copyDuplicatesContents() throws {
        let source = try store.createProfile(named: "工作")
        let fm = FileManager.default
        try "cookie".write(to: source.url.appendingPathComponent("Cookies"),
                           atomically: true, encoding: .utf8)
        try fm.createDirectory(at: source.url.appendingPathComponent("Default/Storage", isDirectory: true),
                               withIntermediateDirectories: true)
        try "value".write(to: source.url.appendingPathComponent("Default/Storage/data.bin"),
                          atomically: true, encoding: .utf8)

        let copy = try store.copyProfile(source, to: "工作 副本")

        #expect(copy.name == "工作 副本")
        #expect(fm.fileExists(atPath: copy.url.appendingPathComponent("Cookies").path))
        #expect(fm.fileExists(atPath: copy.url.appendingPathComponent("Default/Storage/data.bin").path))
        #expect(fm.fileExists(atPath: source.path), "源目录必须保留")
    }

    @Test("空目录也可以复制")
    func copyWithEmptySourceWorks() throws {
        let source = try store.createProfile(named: "空")
        let copy = try store.copyProfile(source, to: "空 副本")
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test("目标已存在时拒绝复制")
    func copyRejectsExistingDestination() throws {
        let source = try store.createProfile(named: "source")
        try store.createProfile(named: "target")

        expectThrows(ProfileStoreError.nameConflict(name: "target")) {
            try store.copyProfile(source, to: "target")
        }
    }

    @Test("目标名称非法时拒绝复制")
    func copyRejectsInvalidDestinationName() throws {
        let source = try store.createProfile(named: "source")
        expectThrows(ProfileNameError.pathTraversal) {
            try store.copyProfile(source, to: "../leak")
        }
    }

    @Test("源目录不存在时报错")
    func copyRejectsMissingSource() throws {
        let ghost = Profile(name: "ghost", url: root.appendingPathComponent("ghost", isDirectory: true))

        let error = caughtError(ProfileStoreError.self) {
            try store.copyProfile(ghost, to: "ghost 副本")
        }
        guard case .notFound? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test("拒绝复制根目录之外的目录")
    func copyRejectsSourceOutsideRoot() throws {
        let outside = temp.makeDirectory("Outside")
        let foreign = Profile(name: "Outside", url: outside)

        let error = caughtError(ProfileStoreError.self) {
            try store.copyProfile(foreign, to: "imported")
        }
        guard case .outsideRoot? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }


    @Test("不可读的目录仍能列出，复制时给出权限错误")
    func unreadableProfileIsListedButCopyFails() throws {
        let source = try store.createProfile(named: "locked")
        try "secret".write(to: source.url.appendingPathComponent("Cookies"),
                           atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        }

        // 列举只需要读取父目录，因此仍然可以看到它。
        #expect(try store.listProfiles().map(\.name) == ["locked"])

        // 复制内容会失败，并且必须以可读的错误返回，而不是静默跳过。
        let error = caughtError(ProfileStoreError.self) {
            try store.copyProfile(source, to: "locked copy")
        }
        switch error {
        case .permissionDenied?, .copyFailed?:
            break
        default:
            Issue.record("unexpected error \(String(describing: error))")
        }
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("locked copy").path
        ))
    }

    // MARK: - Trash

    @Test("删除会把目录移出根目录")
    func trashRemovesDirectoryFromRoot() throws {
        let profile = try store.createProfile(named: "老妈")
        try "cookie".write(to: profile.url.appendingPathComponent("Cookies"),
                           atomically: true, encoding: .utf8)

        try store.trashProfile(profile)

        #expect(!FileManager.default.fileExists(atPath: profile.path))
        #expect(try !store.listProfiles().contains { $0.name == "老妈" })
    }

    @Test("目录不存在时删除报错")
    func trashRejectsMissingDirectory() throws {
        let ghost = Profile(name: "ghost", url: root.appendingPathComponent("ghost", isDirectory: true))

        let error = caughtError(ProfileStoreError.self) { try store.trashProfile(ghost) }
        guard case .notFound? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test("拒绝删除根目录之外的目录")
    func trashRejectsOutsideRoot() throws {
        let outside = temp.makeDirectory("Outside")
        let foreign = Profile(name: "Outside", url: outside)

        let error = caughtError(ProfileStoreError.self) { try store.trashProfile(foreign) }
        guard case .outsideRoot? = error else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: - Lookup

    @Test("按名称查找配置")
    func profileLookupByName() throws {
        _ = try store.createProfile(named: "老爸")
        #expect(store.profile(named: "老爸") != nil)
        #expect(store.profile(named: "老爸 2") == nil)
        #expect(store.profile(named: "a/b") == nil)
    }
}
