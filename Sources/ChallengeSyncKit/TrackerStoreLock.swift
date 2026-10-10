import Darwin
import Foundation

/// Used only by opted-in shared repositories. The stable file must never be
/// replaced or removed while accessors exist. The process mutex covers independent
/// file descriptors in one process; flock covers independent processes.
public final class TrackerStoreLock: Sendable {
    private static let mutex = NSLock()
    private let file: URL
    public init(file: URL) { self.file = file }

    public func withLock<Result>(_ operation: () throws -> Result) throws -> Result {
        Self.mutex.lock()
        defer { Self.mutex.unlock() }
        let fd = open(file.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}
