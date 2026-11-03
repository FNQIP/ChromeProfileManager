import Foundation

public enum ProfileServiceError: LocalizedError, Equatable {
    case sourceInUse(name: String)
    case profileInUse(name: String)
    case runningStateUnknown(reason: String)
    case chromeNotFound(searched: [String])
    case profileMissing(name: String)

    public var errorDescription: String? {
        switch self {
        case .sourceInUse(let name):
            return "配置“\(name)”正在被 Chrome 使用，无法复制。"
        case .profileInUse(let name):
            return "配置“\(name)”正在被 Chrome 使用，无法删除。"
        case .runningStateUnknown(let reason):
            return "无法确认配置是否正在运行，为保护数据已取消该操作。\n\(reason)"
        case .chromeNotFound(let searched):
            return "没有找到 Google Chrome。\n已检查以下位置：\n" + searched.joined(separator: "\n")
        case .profileMissing(let name):
            return "配置“\(name)”的目录已经不存在。"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .sourceInUse, .profileInUse, .runningStateUnknown:
            return "请在 Chrome 中关闭该配置的所有窗口，确认完全退出后重试。本应用不会强制结束 Chrome 进程。"
        case .chromeNotFound:
            return "请安装稳定版 Google Chrome，或将它放回“应用程序”文件夹后重试。"
        case .profileMissing:
            return "请刷新列表，目录可能已被外部删除或重命名。"
        }
    }
}

public struct ProfileEntry: Equatable {
    public let profile: Profile
    public let state: ProfileRunningState

    public init(profile: Profile, state: ProfileRunningState) {
        self.profile = profile
        self.state = state
    }

    public var canOpen: Bool { !state.isRunning }
    public var canModify: Bool { state.allowsDestructiveOperations }
}

public struct MenuSnapshot {
    public let rootURL: URL
    public let entries: [ProfileEntry]
    public let chromeInstallation: ChromeInstallation?
    public let rootError: String?
    public let chromeError: String?
    public let processListingError: String?

    public init(rootURL: URL,
                entries: [ProfileEntry],
                chromeInstallation: ChromeInstallation?,
                rootError: String? = nil,
                chromeError: String? = nil,
                processListingError: String? = nil) {
        self.rootURL = rootURL
        self.entries = entries
        self.chromeInstallation = chromeInstallation
        self.rootError = rootError
        self.chromeError = chromeError
        self.processListingError = processListingError
    }

    public var runningCount: Int {
        entries.filter { $0.state.isRunning }.count
    }

    public var hasChrome: Bool { chromeInstallation != nil }
}

public enum OpenProfileResult: Equatable {
    case launched(pid: Int32)
    case alreadyRunning(pids: [Int32])
}

/// Orchestrates the pieces: directory store, Chrome lookup, launch and the
/// running-state check. Every mutation re-checks the running state first.
public final class ProfileService {

    public let store: ProfileStore
    private let locator: ChromeLocating
    private let launcher: ChromeLaunching
    private let processLister: ProcessListing
    private let fileManager: FileManager

    public init(store: ProfileStore,
                locator: ChromeLocating = ChromeLocator(),
                launcher: ChromeLaunching = ProcessChromeLauncher(),
                processLister: ProcessListing = SystemProcessLister(),
                fileManager: FileManager = .default) {
        self.store = store
        self.locator = locator
        self.launcher = launcher
        self.processLister = processLister
        self.fileManager = fileManager
    }

    public var rootURL: URL { store.rootURL }

    // MARK: - Snapshot

    /// One pass over the filesystem and the process table, used to build the
    /// menu. Called only when the menu opens or after a user action.
    public func snapshot() -> MenuSnapshot {
        var profiles: [Profile] = []
        var rootError: String?

        do {
            profiles = try store.listProfiles()
        } catch {
            rootError = Self.describe(error)
        }

        var processes: [ProcessSnapshot] = []
        var listingError: String?

        do {
            processes = try processLister.snapshot()
        } catch {
            listingError = Self.describe(error)
        }

        let entries = profiles.map { profile -> ProfileEntry in
            let state: ProfileRunningState
            if listingError != nil {
                state = .unknown(reason: listingError ?? "无法读取进程列表。")
            } else {
                state = ChromeUsageDetector.state(for: profile, in: processes)
            }
            return ProfileEntry(profile: profile, state: state)
        }

        var chrome: ChromeInstallation?
        var chromeError: String?
        do {
            chrome = try locator.locate()
        } catch {
            chromeError = Self.describe(error)
        }

        return MenuSnapshot(rootURL: store.rootURL,
                            entries: entries,
                            chromeInstallation: chrome,
                            rootError: rootError,
                            chromeError: chromeError,
                            processListingError: listingError)
    }

    public func runningState(for profile: Profile) -> ProfileRunningState {
        do {
            let processes = try processLister.snapshot()
            return ChromeUsageDetector.state(for: profile, in: processes)
        } catch {
            return .unknown(reason: Self.describe(error))
        }
    }

    // MARK: - Mutations

    @discardableResult
    public func createProfile(named rawName: String) throws -> Profile {
        try store.createProfile(named: rawName)
    }

    /// Copies a profile after verifying that Chrome is not using it.
    @discardableResult
    public func copyProfile(_ source: Profile, toName rawName: String) throws -> Profile {
        try requireNotRunning(source, errorWhenInUse: .sourceInUse(name: source.name))
        return try store.copyProfile(source, to: rawName)
    }

    /// Moves a profile to the Trash after verifying that Chrome is not using it.
    public func trashProfile(_ profile: Profile) throws {
        try requireNotRunning(profile, errorWhenInUse: .profileInUse(name: profile.name))
        try store.trashProfile(profile)
    }

    public func open(_ profile: Profile) throws -> OpenProfileResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: profile.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProfileServiceError.profileMissing(name: profile.name)
        }

        let state = runningState(for: profile)
        if case .running(let pids) = state, !pids.isEmpty {
            return .alreadyRunning(pids: pids)
        }

        let installation: ChromeInstallation
        do {
            installation = try locator.locate()
        } catch {
            if let locatorError = error as? ChromeLocatorError {
                switch locatorError {
                case .notFound(let searched):
                    throw ProfileServiceError.chromeNotFound(searched: searched)
                case .executableMissing:
                    throw error
                }
            }
            throw error
        }

        let pid = try launcher.launch(profileDirectory: profile.url, installation: installation)
        return .launched(pid: pid)
    }

    // MARK: - Helpers

    private func requireNotRunning(_ profile: Profile,
                                   errorWhenInUse: ProfileServiceError) throws {
        switch runningState(for: profile) {
        case .notRunning:
            return
        case .running:
            throw errorWhenInUse
        case .unknown(let reason):
            throw ProfileServiceError.runningStateUnknown(reason: reason)
        }
    }

    static func describe(_ error: Error) -> String {
        guard let localized = error as? LocalizedError,
              let description = localized.errorDescription else {
            return (error as NSError).localizedDescription
        }
        return description
    }
}
