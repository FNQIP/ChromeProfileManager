import Foundation

public enum UninstallError: LocalizedError, Equatable {
    case notAnApplication(path: String)
    case readOnlyLocation(path: String)
    case trashFailed(reason: String)
    case moveVerificationFailed(path: String)

    public var errorDescription: String? {
        switch self {
        case .notAnApplication(let path):
            return "无法卸载：目标不是 .app 应用包。\n\(path)"
        case .readOnlyLocation(let path):
            return "无法卸载：应用所在位置是只读的，无法移入废纸篓。\n\(path)"
        case .trashFailed(let reason):
            return "移入废纸篓失败：\(reason)"
        case .moveVerificationFailed(let path):
            return "移入废纸篓后仍能在原位置找到应用，卸载未完成。\n\(path)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .readOnlyLocation:
            return "如果应用是从 DMG 直接运行的，请先把它拖到「应用程序」再卸载；也可以直接在访达中把应用拖进废纸篓。"
        case .notAnApplication:
            return "请用 Finder 手动删除该应用。"
        default:
            return "请在访达中手动把应用移到废纸篓。配置目录 ~/ChromeProfiles 不会被删除。"
        }
    }
}

/// 把应用自身移入废纸篓，并清理偏好设置。
///
/// 只做两件事：移动 .app、删除本应用的 UserDefaults 域。**从不触碰**
/// `~/ChromeProfiles` 中的浏览数据，也不动 Chrome 的任何一个目录。
public struct AppUninstaller {

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 检查这个 bundle 是否可以安全地移入废纸篓。
    public func validateApplication(at bundleURL: URL) throws {
        let path = bundleURL.path

        guard bundleURL.pathExtension.lowercased() == "app" else {
            throw UninstallError.notAnApplication(path: path)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw UninstallError.notAnApplication(path: path)
        }

        // 从 DMG 首次直接运行时，系统会把它挂到 App Translocation 的只读路径，
        // 那里无法删除自身。
        if path.contains("/AppTranslocation/") {
            throw UninstallError.readOnlyLocation(path: path)
        }

        let parent = bundleURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw UninstallError.readOnlyLocation(path: path)
        }
    }

    /// 把应用移入废纸篓，返回移动后的位置（通常为 nil 或废纸篓内路径）。
    @discardableResult
    public func moveToTrash(_ bundleURL: URL) throws -> URL? {
        try validateApplication(at: bundleURL)

        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: bundleURL, resultingItemURL: &resultingURL)
        } catch {
            throw UninstallError.trashFailed(reason: (error as NSError).localizedDescription)
        }

        guard !fileManager.fileExists(atPath: bundleURL.path) else {
            throw UninstallError.moveVerificationFailed(path: bundleURL.path)
        }

        return resultingURL as URL?
    }

    /// 删除本应用的偏好设置（只有改过根目录才会有内容）。
    public func clearPreferences(domain: String, defaults: UserDefaults = .standard) {
        guard !domain.isEmpty else { return }
        defaults.removePersistentDomain(forName: domain)
    }
}
