import Foundation

/// Stored preferences. The first release only keeps the profile root, which is
/// all the UI needs; there is no settings database and no background syncing.
public struct Preferences {

    public static let defaultRootPath = "~/ChromeProfiles"
    private static let rootDefaultsKey = "ProfileRootPath"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The standard location, expanded to an absolute path.
    public static var defaultRootURL: URL {
        URL(fileURLWithPath: (defaultRootPath as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    /// Custom root as stored, or nil when the default is in use.
    public var customRootPath: String? {
        get {
            guard let stored = defaults.string(forKey: Self.rootDefaultsKey), !stored.isEmpty else {
                return nil
            }
            return stored
        }
        nonmutating set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Self.rootDefaultsKey)
            } else {
                defaults.removeObject(forKey: Self.rootDefaultsKey)
            }
        }
    }

    public var isUsingDefaultRoot: Bool { customRootPath == nil }

    public var rootURL: URL {
        guard let stored = customRootPath else { return Self.defaultRootURL }
        return URL(fileURLWithPath: (stored as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    /// Points the app at another root.
    ///
    /// The directory is created when missing and must be writable. Existing
    /// profiles in the previous root are never moved or deleted — switching is
    /// purely a change of which folder is displayed.
    public func setRootURL(_ url: URL, fileManager: FileManager = .default) throws {
        var isDirectory: ObjCBool = false
        let path = url.standardizedFileURL.path

        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ProfileStoreError.rootIsNotDirectory(path: path)
            }
            guard fileManager.isWritableFile(atPath: path) else {
                throw ProfileStoreError.rootNotWritable(path: path)
            }
        } else {
            do {
                try fileManager.createDirectory(at: url.standardizedFileURL, withIntermediateDirectories: true)
            } catch {
                throw ProfileStoreError.translate(error, path: path) {
                    .rootUnavailable(path: path, reason: $0)
                }
            }
        }

        customRootPath = path
    }

    public func resetRoot() {
        customRootPath = nil
    }
}
