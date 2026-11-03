import Foundation

/// One row of the process table: pid, executable and full argv.
public struct ProcessSnapshot: Equatable {
    public let pid: Int32
    public let executablePath: String
    public let arguments: [String]

    public init(pid: Int32, executablePath: String, arguments: [String]) {
        self.pid = pid
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public enum ProcessListingError: LocalizedError, Equatable {
    case enumerationFailed(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .enumerationFailed(let code):
            return "无法读取系统进程列表（errno \(code)）。"
        }
    }

    public var recoverySuggestion: String? {
        "请先退出 Chrome 后重试，或重新启动本应用。"
    }
}

public protocol ProcessListing {
    func snapshot() throws -> [ProcessSnapshot]
}

/// Decodes the buffer returned by `sysctl(KERN_PROCARGS2)`.
///
/// Layout: `int argc`, the executable path as a C string, zero padding, then
/// `argc` NUL-terminated arguments. Splitting it here keeps the syscall
/// plumbing out of the matching logic and makes the parser unit-testable.
public enum ProcessCommandLineParser {

    public static func parse(_ buffer: [UInt8]) -> (executablePath: String, arguments: [String])? {
        let headerSize = MemoryLayout<Int32>.size
        guard buffer.count > headerSize else { return nil }

        let argc = Int32(bitPattern:
            UInt32(buffer[0])
            | UInt32(buffer[1]) << 8
            | UInt32(buffer[2]) << 16
            | UInt32(buffer[3]) << 24
        )
        guard argc >= 0, argc < 4096 else { return nil }

        var index = headerSize

        // Executable path, NUL terminated.
        let pathStart = index
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        guard index <= buffer.count else { return nil }
        let executablePath = String(decoding: buffer[pathStart..<index], as: UTF8.self)

        // Kernel padding between the path and argv.
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        arguments.reserveCapacity(Int(argc))

        for _ in 0..<Int(argc) {
            guard index < buffer.count else { break }
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            if index < buffer.count { index += 1 }
        }

        guard !executablePath.isEmpty else { return nil }
        return (executablePath, arguments)
    }
}

/// Reads argv for every visible process using `sysctl`.
///
/// `ps` output is deliberately avoided: it joins argv with spaces, which makes
/// paths that contain spaces ambiguous. `KERN_PROCARGS2` keeps the original NUL
/// separated argv intact.
public struct SystemProcessLister: ProcessListing {

    public init() {}

    public func snapshot() throws -> [ProcessSnapshot] {
        var result: [ProcessSnapshot] = []
        let pids = try Self.allProcessIdentifiers()
        result.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let entry = Self.commandLine(for: pid) else { continue }
            result.append(ProcessSnapshot(pid: pid,
                                          executablePath: entry.executablePath,
                                          arguments: entry.arguments))
        }
        return result
    }

    // MARK: - sysctl

    static func allProcessIdentifiers() throws -> [Int32] {
        let stride = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0

        let probe = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, u_int(pointer.count), nil, &size, nil, 0)
        }
        guard probe == 0, size > 0 else {
            throw ProcessListingError.enumerationFailed(errno: errno)
        }

        // Leave headroom: processes can appear between the two calls.
        var capacity = size / stride + 32
        var pids: [Int32] = []

        for _ in 0..<3 {
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var actualSize = capacity * stride

            let status = mib.withUnsafeMutableBufferPointer { pointer in
                buffer.withUnsafeMutableBytes { raw in
                    sysctl(pointer.baseAddress, u_int(pointer.count), raw.baseAddress, &actualSize, nil, 0)
                }
            }

            guard status == 0 else {
                throw ProcessListingError.enumerationFailed(errno: errno)
            }

            let count = actualSize / stride
            if count >= capacity {
                capacity *= 2
                continue
            }

            pids.removeAll(keepingCapacity: true)
            for offset in 0..<count {
                pids.append(buffer[offset].kp_proc.p_pid)
            }
            return pids
        }

        return pids
    }

    static func commandLine(for pid: Int32) -> (executablePath: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0

        let probe = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, u_int(pointer.count), nil, &size, nil, 0)
        }
        guard probe == 0, size > MemoryLayout<Int32>.size else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let status = mib.withUnsafeMutableBufferPointer { pointer in
            buffer.withUnsafeMutableBytes { raw in
                sysctl(pointer.baseAddress, u_int(pointer.count), raw.baseAddress, &size, nil, 0)
            }
        }
        guard status == 0 else { return nil }

        if size < buffer.count {
            buffer.removeLast(buffer.count - size)
        }

        return ProcessCommandLineParser.parse(buffer)
    }
}
