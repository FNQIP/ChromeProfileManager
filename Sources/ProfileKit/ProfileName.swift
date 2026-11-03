import Foundation

/// Errors produced while validating a user-supplied profile name.
public enum ProfileNameError: LocalizedError, Equatable {
    case empty
    case whitespaceOnly
    case tooLong(max: Int)
    case containsPathSeparator
    case pathTraversal
    case hiddenName
    case containsControlCharacters

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "名称不能为空。"
        case .whitespaceOnly:
            return "名称不能只由空格组成。"
        case .tooLong(let max):
            return "名称过长，最多 \(max) 个字符。"
        case .containsPathSeparator:
            return "名称不能包含 “/” 或 “:”，它们会被当作路径分隔符。"
        case .pathTraversal:
            return "名称不能是 “.” 或 “..”，也不能包含连续的 “..”。"
        case .hiddenName:
            return "名称不能以 “.” 开头，否则目录会被系统隐藏。"
        case .containsControlCharacters:
            return "名称不能包含换行符、制表符等控制字符。"
        }
    }

    public var recoverySuggestion: String? {
        "请换一个只包含普通字符的名称，例如“工作”“个人”或“测试环境”。"
    }
}

/// Validation rules for the name of a profile directory.
///
/// A profile name becomes a single path component directly below the profile
/// root, therefore it must never be able to escape that root or produce a
/// nested path.
public enum ProfileName {
    public static let maximumLength = 100

    /// Returns the trimmed, validated name or throws `ProfileNameError`.
    public static func validated(_ raw: String) throws -> String {
        if raw.isEmpty {
            throw ProfileNameError.empty
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            throw ProfileNameError.whitespaceOnly
        }

        if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw ProfileNameError.containsControlCharacters
        }

        // Traversal is checked before separators so that "../escape" is
        // reported as the more specific problem.
        if trimmed == "." || trimmed == ".." || trimmed.contains("..") {
            throw ProfileNameError.pathTraversal
        }

        // "/" separates path components; ":" is the classic Mac separator and
        // is still normalised to "/" by Finder.
        if trimmed.contains("/") || trimmed.contains(":") {
            throw ProfileNameError.containsPathSeparator
        }

        if trimmed.hasPrefix(".") {
            throw ProfileNameError.hiddenName
        }

        if trimmed.count > maximumLength {
            throw ProfileNameError.tooLong(max: maximumLength)
        }

        return trimmed
    }

    /// Non-throwing convenience used to drive menu enablement.
    public static func isValid(_ raw: String) -> Bool {
        (try? validated(raw)) != nil
    }
}
