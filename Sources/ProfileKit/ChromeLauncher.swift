import Foundation

/// Builds the argv Chrome receives for one profile.
///
/// The value is always passed as a single, separate argv element. Nothing is
/// ever concatenated into a shell string, so spaces, CJK characters, quotes and
/// other special characters in a directory name are safe by construction.
public enum ChromeLaunchArguments {
    public static let userDataDirPrefix = "--user-data-dir="
    public static let newWindowFlag = "--new-window"

    public static func make(for profileDirectory: URL) -> [String] {
        let path = PathHelpers.canonicalPath(for: profileDirectory)
        return [userDataDirPrefix + path, newWindowFlag]
    }
}

public enum ChromeLaunchError: LocalizedError, Equatable {
    case executableMissing(path: String)
    case launchFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "Chrome 可执行文件不可用：\(path)"
        case .launchFailed(let path, let reason):
            return "启动 Chrome 失败：\(reason)\n程序路径：\(path)"
        }
    }

    public var recoverySuggestion: String? {
        "请确认 Chrome 可以正常从“应用程序”启动，然后重试。现有配置数据不会被修改。"
    }
}

public protocol ChromeLaunching {
    /// Launches Chrome with the given profile and returns the spawned pid.
    func launch(profileDirectory: URL, installation: ChromeInstallation) throws -> Int32
}

public struct ProcessChromeLauncher: ChromeLaunching {

    public init() {}

    public func launch(profileDirectory: URL, installation: ChromeInstallation) throws -> Int32 {
        let executable = installation.executableURL

        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ChromeLaunchError.executableMissing(path: executable.path)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ChromeLaunchArguments.make(for: profileDirectory)

        do {
            try process.run()
        } catch {
            throw ChromeLaunchError.launchFailed(
                path: executable.path,
                reason: (error as NSError).localizedDescription
            )
        }

        return process.processIdentifier
    }
}
