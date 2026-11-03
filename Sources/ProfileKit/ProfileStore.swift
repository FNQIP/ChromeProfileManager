import Foundation

/// File-system operations for the profile root.
///
/// This type knows nothing about menus or Chrome: it only creates, lists,
/// copies and trashes first-level directories below the root. Every mutation is
/// constrained to a direct child of the root so a bad name can never recurse
/// over the whole root.
public final class ProfileStore {

    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    // MARK: - Root

    /// Creates the root when missing, or reports why it cannot be used.
    public func ensureRootExists() throws {
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ProfileStoreError.rootIsNotDirectory(path: rootURL.path)
            }
            guard fileManager.isWritableFile(atPath: rootURL.path) else {
                throw ProfileStoreError.rootNotWritable(path: rootURL.path)
            }
            return
        }

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            throw ProfileStoreError.translate(error, path: rootURL.path) {
                .rootUnavailable(path: self.rootURL.path, reason: $0)
            }
        }
    }

    /// True when the root exists and can be written to.
    public func isRootUsable() -> Bool {
        (try? ensureRootExists()) != nil
    }

    // MARK: - Listing

    /// Every first-level directory below the root, sorted the way Finder sorts.
    ///
    /// Hidden entries are skipped, and symbolic links are ignored so that a link
    /// can never redirect a delete into another location.
    public func listProfiles() throws -> [Profile] {
        try ensureRootExists()

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .nameKey]
        let contents: [URL]

        do {
            contents = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ProfileStoreError.translate(error, path: rootURL.path) {
                .enumerationFailed(reason: $0)
            }
        }

        var profiles: [Profile] = []
        profiles.reserveCapacity(contents.count)

        for url in contents {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.isDirectory == true else { continue }
            guard values.isSymbolicLink != true else { continue }
            profiles.append(Profile(name: url.lastPathComponent, url: url))
        }

        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return profiles
    }

    /// Looks up an existing profile by exact name.
    public func profile(named rawName: String) -> Profile? {
        guard let name = try? ProfileName.validated(rawName) else { return nil }
        let url = rootURL.appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return Profile(name: name, url: url)
    }

    // MARK: - Mutations

    @discardableResult
    public func createProfile(named rawName: String) throws -> Profile {
        let name = try ProfileName.validated(rawName)
        try ensureRootExists()

        let destination = rootURL.appendingPathComponent(name, isDirectory: true)
        try assertDirectChild(destination)

        if fileManager.fileExists(atPath: destination.path) {
            throw ProfileStoreError.nameConflict(name: name)
        }

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        } catch {
            if Self.isAlreadyExists(error) {
                throw ProfileStoreError.nameConflict(name: name)
            }
            throw ProfileStoreError.translate(error, path: destination.path) {
                .createFailed(name: name, reason: $0)
            }
        }

        return Profile(name: name, url: destination)
    }

    /// Copies a profile's whole directory. The source must not be in use; that
    /// check happens in `ProfileService` before this is called.
    @discardableResult
    public func copyProfile(_ source: Profile, to rawName: String) throws -> Profile {
        let name = try ProfileName.validated(rawName)
        try ensureRootExists()

        try assertDirectChild(source.url)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ProfileStoreError.notFound(path: source.path)
        }
        guard isDirectory.boolValue else {
            throw ProfileStoreError.notADirectory(path: source.path)
        }

        let destination = rootURL.appendingPathComponent(name, isDirectory: true)
        try assertDirectChild(destination)

        if fileManager.fileExists(atPath: destination.path) {
            throw ProfileStoreError.nameConflict(name: name)
        }

        do {
            try fileManager.copyItem(at: source.url, to: destination)
        } catch {
            if Self.isAlreadyExists(error) {
                throw ProfileStoreError.nameConflict(name: name)
            }
            throw ProfileStoreError.translate(error, path: destination.path) {
                .copyFailed(name: name, reason: $0)
            }
        }

        // Requirement: never report success before the destination exists.
        var destinationIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory),
              destinationIsDirectory.boolValue else {
            throw ProfileStoreError.copyVerificationFailed(name: name)
        }

        return Profile(name: name, url: destination)
    }

    /// Moves a profile directory to the macOS Trash instead of deleting it.
    public func trashProfile(_ profile: Profile) throws {
        try assertDirectChild(profile.url)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: profile.path, isDirectory: &isDirectory) else {
            throw ProfileStoreError.notFound(path: profile.path)
        }
        guard isDirectory.boolValue else {
            throw ProfileStoreError.notADirectory(path: profile.path)
        }

        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: profile.url, resultingItemURL: &resultingURL)
        } catch {
            throw ProfileStoreError.translate(error, path: profile.path) {
                .trashFailed(name: profile.name, reason: $0)
            }
        }
    }

    // MARK: - Helpers

    private func assertDirectChild(_ url: URL) throws {
        guard PathHelpers.isDirectChild(url.path, of: rootURL.path) else {
            throw ProfileStoreError.outsideRoot(path: url.path)
        }
    }

    private static func isAlreadyExists(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSPOSIXErrorDomain,
           POSIXErrorCode(rawValue: Int32(nsError.code)) == .EEXIST {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteFileExistsError {
            return true
        }
        return false
    }
}
