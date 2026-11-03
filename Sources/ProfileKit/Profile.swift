import Foundation

/// A single managed profile: one first-level directory below the profile root.
///
/// This is *not* a Chrome-internal profile such as `Default` or `Profile 1`;
/// it is the whole `--user-data-dir` root that Chrome is launched with.
public struct Profile: Hashable, Identifiable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url.standardizedFileURL
    }

    public var id: String { url.path }

    /// Canonical path used for process matching and display.
    public var path: String { url.path }
}

extension Profile: CustomStringConvertible {
    public var description: String { "Profile(\(name) at \(path))" }
}

/// Running state of the Chrome instance that owns a profile directory.
public enum ProfileRunningState: Equatable, Sendable {
    case notRunning
    case running(pids: [Int32])
    /// The state could not be determined (for example the process list was
    /// unreadable). Callers must treat this conservatively.
    case unknown(reason: String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    /// Copy and delete are only allowed when we are certain Chrome is not
    /// using the directory.
    public var allowsDestructiveOperations: Bool {
        self == .notRunning
    }

    public var displayText: String {
        switch self {
        case .notRunning:
            return "未运行"
        case .running(let pids):
            return pids.count == 1 ? "运行中" : "运行中（\(pids.count) 个进程）"
        case .unknown:
            return "状态未知"
        }
    }
}
