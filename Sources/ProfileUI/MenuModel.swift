import Foundation
import ProfileKit

/// Warning rows shown above the profile list.
public enum MenuWarning: Equatable {
    case rootUnavailable(message: String)
    case chromeMissing(message: String)
    case processListingUnavailable(message: String)

    public var title: String {
        switch self {
        case .rootUnavailable: return "⚠︎ 配置根目录不可用"
        case .chromeMissing: return "⚠︎ 未找到 Google Chrome"
        case .processListingUnavailable: return "⚠︎ 无法读取进程列表"
        }
    }

    public var detail: String {
        switch self {
        case .rootUnavailable(let message),
             .chromeMissing(let message),
             .processListingUnavailable(let message):
            return message
        }
    }
}

/// Menu-level commands.
public enum MenuCommand: String, Equatable, CaseIterable {
    case newProfile
    case refresh
    case openRoot
    case preferences
    case uninstall
    case quit

    public var title: String {
        switch self {
        case .newProfile: return "新建配置…"
        case .refresh: return "刷新列表"
        case .openRoot: return "打开配置根目录"
        case .preferences: return "偏好设置…"
        case .uninstall: return "卸载 Chrome Profiles…"
        case .quit: return "退出 Chrome Profiles"
        }
    }

    /// Key equivalents shown in the menu, limited to the few worth memorising.
    public var keyEquivalent: String {
        switch self {
        case .newProfile: return "n"
        case .refresh: return "r"
        case .preferences: return ","
        case .quit: return "q"
        case .openRoot: return ""
        case .uninstall: return ""
        }
    }
}

/// One row of the status menu.
public enum MenuRow: Equatable {
    case header(profileCount: Int, runningCount: Int)
    case warning(MenuWarning)
    case profile(ProfileEntry)
    case emptyState
    case command(MenuCommand)
    case separator
}

/// Pure presentation model: turns a `MenuSnapshot` into the rows the menu shows.
///
/// Keeping this free of AppKit makes the menu structure, ordering and
/// enablement rules testable in CI without a window server.
public struct MenuModel: Equatable {

    public let rows: [MenuRow]

    public init(rows: [MenuRow]) {
        self.rows = rows
    }

    public static func make(from snapshot: MenuSnapshot) -> MenuModel {
        var rows: [MenuRow] = []

        rows.append(.header(profileCount: snapshot.entries.count,
                            runningCount: snapshot.runningCount))
        rows.append(.separator)

        if let rootError = snapshot.rootError {
            rows.append(.warning(.rootUnavailable(message: rootError)))
        }
        if !snapshot.hasChrome {
            rows.append(.warning(.chromeMissing(message: snapshot.chromeError ?? "")))
        }
        if let listingError = snapshot.processListingError {
            rows.append(.warning(.processListingUnavailable(message: listingError)))
        }

        if snapshot.entries.isEmpty {
            // An unreadable root already has its own warning row; showing
            // "还没有配置" next to it would be misleading.
            if snapshot.rootError == nil {
                rows.append(.emptyState)
            }
        } else {
            for entry in snapshot.entries {
                rows.append(.profile(entry))
            }
        }

        rows.append(.separator)
        rows.append(.command(.newProfile))
        rows.append(.command(.refresh))
        rows.append(.command(.openRoot))
        rows.append(.command(.preferences))
        rows.append(.separator)
        rows.append(.command(.uninstall))
        rows.append(.separator)
        rows.append(.command(.quit))

        return MenuModel(rows: rows)
    }

    /// The rows that end up as clickable profile entries.
    public var profileEntries: [ProfileEntry] {
        rows.compactMap { row in
            if case .profile(let entry) = row { return entry }
            return nil
        }
    }

    public var warnings: [MenuWarning] {
        rows.compactMap { row in
            if case .warning(let warning) = row { return warning }
            return nil
        }
    }
}
