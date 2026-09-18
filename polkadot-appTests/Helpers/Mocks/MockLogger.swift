import Foundation
import SDKLogger

// MARK: - Mock Logger

/// Silent logger that records warnings and errors for assertions.
final class MockLogger: SDKLoggerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedWarnings: [String] = []
    private var recordedErrors: [String] = []

    var warnings: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedWarnings
    }

    var errors: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedErrors
    }

    func verbose(message _: () -> String, file _: String, function _: String, line _: Int) {}
    func debug(message _: () -> String, file _: String, function _: String, line _: Int) {}
    func info(message _: () -> String, file _: String, function _: String, line _: Int) {}

    func warning(message: () -> String, file _: String, function _: String, line _: Int) {
        lock.lock()
        defer { lock.unlock() }
        recordedWarnings.append(message())
    }

    func error(message: () -> String, file _: String, function _: String, line _: Int) {
        lock.lock()
        defer { lock.unlock() }
        recordedErrors.append(message())
    }
}
