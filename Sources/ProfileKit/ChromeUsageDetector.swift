import Foundation

/// Decides whether a Chrome process is currently using a given profile folder.
///
/// Matching is done on the canonical form of the `--user-data-dir` value, so
/// `~/ChromeProfiles/我` is never confused with `~/ChromeProfiles/我（副）`.
public enum ChromeUsageDetector {

    public static let userDataDirFlag = "--user-data-dir"

    /// Chrome's browser and helper processes all live inside a `.app` bundle.
    public static func isChromeProcess(_ process: ProcessSnapshot) -> Bool {
        let path = process.executablePath
        guard path.contains("Google Chrome") else { return false }
        return path.contains(".app/Contents/MacOS/") || path.contains(".framework/")
    }

    /// Extracts the raw `--user-data-dir` value from an argv list.
    public static func userDataDirValue(in arguments: [String]) -> String? {
        for argument in arguments {
            if argument.hasPrefix(userDataDirFlag + "=") {
                return String(argument.dropFirst(userDataDirFlag.count + 1))
            }
            if argument.hasPrefix("-" + userDataDirFlag + "=") {
                return String(argument.dropFirst(userDataDirFlag.count + 2))
            }
        }

        for (index, argument) in arguments.enumerated() {
            if argument == userDataDirFlag || argument == "-" + userDataDirFlag {
                if index + 1 < arguments.count {
                    return arguments[index + 1]
                }
            }
        }

        return nil
    }

    /// Pids of Chrome processes whose `--user-data-dir` matches the profile.
    public static func pidsUsing(userDataDirectory: URL,
                                 in processes: [ProcessSnapshot]) -> [Int32] {
        let target = PathHelpers.canonicalPath(for: userDataDirectory)

        var pids: [Int32] = []
        for process in processes where isChromeProcess(process) {
            guard let rawValue = userDataDirValue(in: process.arguments),
                  !rawValue.isEmpty else { continue }
            let candidate = PathHelpers.canonicalPath(rawValue)
            if PathHelpers.pathsReferToSameLocation(candidate, target) {
                pids.append(process.pid)
            }
        }
        return pids
    }

    public static func state(for profile: Profile,
                             in processes: [ProcessSnapshot]) -> ProfileRunningState {
        let pids = pidsUsing(userDataDirectory: profile.url, in: processes)
        return pids.isEmpty ? .notRunning : .running(pids: pids)
    }
}
