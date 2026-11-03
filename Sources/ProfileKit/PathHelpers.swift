import Foundation

/// Path normalisation shared by the directory layer and the process matcher.
///
/// Chrome normalises the value it receives for `--user-data-dir`, so matching a
/// process against a profile must compare canonical paths instead of raw
/// strings. Two different profiles such as `我` and `我（副）` must never be
/// considered the same directory.
public enum PathHelpers {

    /// Expands a leading `~`, standardises the path and resolves symlinks.
    /// Trailing slashes are removed so `/a/b/` and `/a/b` compare equal.
    public static func canonicalPath(_ raw: String) -> String {
        var path = raw
        if path.hasPrefix("~") {
            path = (path as NSString).expandingTildeInPath
        }
        guard !path.isEmpty else { return "" }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        var result = resolved.path

        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    public static func canonicalPath(for url: URL) -> String {
        canonicalPath(url.path)
    }

    /// Exact comparison first, then a case-insensitive comparison because the
    /// default APFS volume is case-insensitive. Being slightly over-eager here
    /// only ever *blocks* a destructive operation, which is the safe direction.
    public static func pathsReferToSameLocation(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs.compare(rhs, options: .caseInsensitive) == .orderedSame {
            return true
        }
        return canonicalPath(lhs) == canonicalPath(rhs)
    }

    /// True when `path` is a direct child of `parent`.
    public static func isDirectChild(_ path: String, of parent: String) -> Bool {
        let childURL = URL(fileURLWithPath: path).standardizedFileURL
        let parentURL = URL(fileURLWithPath: parent).standardizedFileURL
        return childURL.deletingLastPathComponent().path == parentURL.path
    }
}
