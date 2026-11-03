import Foundation
import Testing

/// A throw-away directory tree, created per test and removed afterwards.
final class TemporaryDirectory {
    let url: URL

    init(prefix: String = "cpm-tests") {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) -> URL {
        let target = url.appendingPathComponent(relativePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    @discardableResult
    func writeFile(_ relativePath: String, contents: String = "data") -> URL {
        let target = url.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? contents.data(using: .utf8)?.write(to: target)
        return target
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Asserts that `body` throws exactly `expected`.
func expectThrows<E: Error & Equatable>(_ expected: E,
                                        _ body: () throws -> Void) {
    do {
        try body()
        Issue.record("expected \(expected) but nothing was thrown")
    } catch let error as E {
        #expect(error == expected, "expected \(expected), got \(error)")
    } catch {
        Issue.record("expected \(expected), got \(error)")
    }
}

/// Runs `body` and returns the thrown error of the requested type, if any.
func caughtError<E: Error>(_ type: E.Type, _ body: () throws -> Void) -> E? {
    do {
        try body()
        Issue.record("expected \(type) to be thrown, but nothing was thrown")
        return nil
    } catch let error as E {
        return error
    } catch {
        Issue.record("expected \(type), got \(error)")
        return nil
    }
}
