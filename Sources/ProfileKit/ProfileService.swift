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

public struct ProfileEntry: Equatable, Sendable {
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

/// 一次扫描的原始结果：目录列表、每个配置的运行状态、Chrome 定位结果。
///
/// 拆开保存是为了让界面可以「同步列举目录 + 缓存运行状态 + 后台刷新状态」，
/// 既保证打开菜单时目录信息是最新的，又不必在主线程等待进程扫描。
public struct ScanResult {
    public let rootURL: URL
    public let profiles: [Profile]
    public let rootError: String?
    public let states: [String: ProfileRunningState]
    public let processListingError: String?
    public let chromeInstallation: ChromeInstallation?
    public let chromeError: String?

    public init(rootURL: URL,
                profiles: [Profile],
                rootError: String? = nil,
                states: [String: ProfileRunningState] = [:],
                processListingError: String? = nil,
                chromeInstallation: ChromeInstallation? = nil,
                chromeError: String? = nil) {
        self.rootURL = rootURL
        self.profiles = profiles
        self.rootError = rootError
        self.states = states
        self.processListingError = processListingError
        self.chromeInstallation = chromeInstallation
        self.chromeError = chromeError
    }

    /// 没有缓存状态时：进程表可读则视为未运行；进程表不可读则保守为未知。
    public func state(for profile: Profile) -> ProfileRunningState {
        if let state = states[profile.path] { return state }
        if let processListingError { return .unknown(reason: processListingError) }
        return .notRunning
    }

    public func snapshot() -> MenuSnapshot {
        let entries = profiles.map { profile in
            ProfileEntry(profile: profile, state: state(for: profile))
        }
        return MenuSnapshot(rootURL: rootURL,
                            entries: entries,
                            chromeInstallation: chromeInstallation,
                            rootError: rootError,
                            chromeError: chromeError,
                            processListingError: processListingError)
    }
}

public enum OpenProfileResult: Equatable {
    case launched(pid: Int32)
    case alreadyRunning(pids: [Int32])
}

/// Orchestrates the pieces: directory store, Chrome lookup, launch and the
/// running-state check. Every mutation re-checks the running state first.
public final class ProfileService: @unchecked Sendable {

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

    // MARK: - Scanning

    /// 目录列举只做一次 readdir，开销很小，因此每次打开菜单都同步执行，
    /// 保证外部新建/删除/重命名的目录立刻可见。
    public func listProfiles() -> (profiles: [Profile], error: String?) {
        do {
            return (try store.listProfiles(), nil)
        } catch {
            return ([], Self.describe(error))
        }
    }

    /// 遍历一次进程表，按配置路径返回运行状态。开销较大（每个进程一次
    /// sysctl），调用方应放在后台队列执行。
    public func scanRunningStates(for profiles: [Profile])
        -> (states: [String: ProfileRunningState], error: String?) {

        do {
            let snapshot = try processLister.snapshot()
            var states: [String: ProfileRunningState] = [:]
            states.reserveCapacity(profiles.count)
            for profile in profiles {
                states[profile.path] = ChromeUsageDetector.state(for: profile, in: snapshot)
            }
            return (states, nil)
        } catch {
            let message = Self.describe(error)
            var states: [String: ProfileRunningState] = [:]
            states.reserveCapacity(profiles.count)
            for profile in profiles {
                states[profile.path] = .unknown(reason: message)
            }
            return (states, message)
        }
    }

    public func chromeStatus() -> (installation: ChromeInstallation?, error: String?) {
        do {
            return (try locator.locate(), nil)
        } catch {
            return (nil, Self.describe(error))
        }
    }

    /// 完整同步扫描：目录 + 进程 + Chrome。用于测试、诊断与首次打开菜单。
    public func scan() -> ScanResult {
        let listing = listProfiles()
        let states = scanRunningStates(for: listing.profiles)
        let chrome = chromeStatus()

        return ScanResult(rootURL: store.rootURL,
                          profiles: listing.profiles,
                          rootError: listing.error,
                          states: states.states,
                          processListingError: states.error,
                          chromeInstallation: chrome.installation,
                          chromeError: chrome.error)
    }

    /// 一次完整的同步快照，等价于 `scan().snapshot()`。
    public func snapshot() -> MenuSnapshot {
        scan().snapshot()
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
