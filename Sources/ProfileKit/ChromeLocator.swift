import Foundation

/// A Google Chrome installation on disk.
public struct ChromeInstallation: Equatable {
    public let bundleURL: URL

    public init(bundleURL: URL) {
        self.bundleURL = bundleURL.standardizedFileURL
    }

    public var executableURL: URL {
        bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("Google Chrome")
    }

    public static let bundleIdentifier = "com.google.Chrome"
}

public enum ChromeLocatorError: LocalizedError, Equatable {
    case notFound(searched: [String])
    case executableMissing(bundlePath: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let searched):
            return "没有找到 Google Chrome。\n已检查以下位置：\n" + searched.joined(separator: "\n")
        case .executableMissing(let bundlePath):
            return "找到了 Chrome 应用包，但其中缺少可执行文件：\(bundlePath)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "请安装稳定版 Google Chrome，或将它放回“应用程序”文件夹后重试。"
        case .executableMissing:
            return "Chrome 安装可能已损坏，建议重新安装稳定版 Google Chrome。"
        }
    }
}

public protocol ChromeLocating {
    var searchedPaths: [String] { get }
    func locate() throws -> ChromeInstallation
}

/// Looks for stable Google Chrome in the standard application folders.
public struct ChromeLocator: ChromeLocating {
    public static let defaultCandidatePaths = [
        "/Applications/Google Chrome.app",
        "~/Applications/Google Chrome.app"
    ]

    private let candidatePaths: [String]
    private let fileManager: FileManager

    public init(candidatePaths: [String] = ChromeLocator.defaultCandidatePaths,
                fileManager: FileManager = .default) {
        self.candidatePaths = candidatePaths
        self.fileManager = fileManager
    }

    public var searchedPaths: [String] {
        candidatePaths.map { ($0 as NSString).expandingTildeInPath }
    }

    public func locate() throws -> ChromeInstallation {
        for candidate in candidatePaths {
            let expanded = (candidate as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let installation = ChromeInstallation(bundleURL: URL(fileURLWithPath: expanded))
            guard fileManager.isExecutableFile(atPath: installation.executableURL.path) else {
                throw ChromeLocatorError.executableMissing(bundlePath: installation.bundleURL.path)
            }
            return installation
        }

        throw ChromeLocatorError.notFound(searched: searchedPaths)
    }
}
