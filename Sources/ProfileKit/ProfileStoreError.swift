import Foundation

/// Every failure of the profile directory layer, phrased for end users.
public enum ProfileStoreError: LocalizedError, Equatable {
    case rootUnavailable(path: String, reason: String)
    case rootIsNotDirectory(path: String)
    case rootNotWritable(path: String)
    case nameConflict(name: String)
    case notFound(path: String)
    case notADirectory(path: String)
    case outsideRoot(path: String)
    case permissionDenied(path: String)
    case diskFull(path: String)
    case createFailed(name: String, reason: String)
    case copyFailed(name: String, reason: String)
    case copyVerificationFailed(name: String)
    case trashFailed(name: String, reason: String)
    case enumerationFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .rootUnavailable(let path, let reason):
            return "无法访问配置根目录：\(path)\n\(reason)"
        case .rootIsNotDirectory(let path):
            return "配置根目录路径被一个普通文件占用：\(path)"
        case .rootNotWritable(let path):
            return "配置根目录不可写入：\(path)"
        case .nameConflict(let name):
            return "已经存在名为“\(name)”的配置。"
        case .notFound(let path):
            return "目录不存在：\(path)"
        case .notADirectory(let path):
            return "目标不是目录：\(path)"
        case .outsideRoot(let path):
            return "出于安全考虑，只能操作配置根目录下的第一层目录：\(path)"
        case .permissionDenied(let path):
            return "没有权限访问：\(path)"
        case .diskFull(let path):
            return "磁盘空间不足，操作未能完成：\(path)"
        case .createFailed(let name, let reason):
            return "创建配置“\(name)”失败：\(reason)"
        case .copyFailed(let name, let reason):
            return "复制配置“\(name)”失败：\(reason)"
        case .copyVerificationFailed(let name):
            return "复制配置“\(name)”后没有找到目标目录，复制可能未完成。"
        case .trashFailed(let name, let reason):
            return "将配置“\(name)”移入废纸篓失败：\(reason)"
        case .enumerationFailed(let reason):
            return "读取配置列表失败：\(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .nameConflict:
            return "请换一个名称。现有目录不会被覆盖。"
        case .rootNotWritable, .permissionDenied:
            return "请检查该目录的权限，或在“偏好设置”中选择一个可写入的目录。"
        case .diskFull:
            return "请清理磁盘空间后重试。"
        case .outsideRoot:
            return "请刷新列表后再试。"
        default:
            return nil
        }
    }

    /// Maps Cocoa / POSIX errors onto user-facing cases.
    static func translate(_ error: Error,
                          path: String,
                          fallback: (String) -> ProfileStoreError) -> ProfileStoreError {
        let nsError = error as NSError

        if nsError.domain == NSPOSIXErrorDomain {
            switch POSIXErrorCode(rawValue: Int32(nsError.code)) {
            case .EACCES, .EPERM, .EROFS:
                return .permissionDenied(path: path)
            case .ENOSPC, .EDQUOT:
                return .diskFull(path: path)
            case .ENOENT:
                return .notFound(path: path)
            default:
                break
            }
        }

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied(path: path)
            case NSFileWriteOutOfSpaceError:
                return .diskFull(path: path)
            case NSFileReadNoSuchFileError:
                return .notFound(path: path)
            default:
                break
            }
        }

        return fallback(nsError.localizedDescription)
    }
}
