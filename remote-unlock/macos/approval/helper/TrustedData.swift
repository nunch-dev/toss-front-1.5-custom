import Darwin
import Foundation

enum HelperError: Error {
    case rejected, cancelled
}

enum TrustedData {
    // Takes ownership even on error. Never trusts the size observed by open.
    static func consume(_ fd: Int32, maximumBytes: Int) throws -> Data {
        guard fd >= 0 else { throw HelperError.rejected }
        defer { close(fd) }
        guard maximumBytes > 0, maximumBytes < Int.max else { throw HelperError.rejected }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(4096, maximumBytes + 1))
        while true {
            let limit = min(buffer.count, maximumBytes + 1 - result.count)
            let count = read(fd, &buffer, limit)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw HelperError.rejected }
            if count == 0 { return result }
            guard count <= maximumBytes - result.count else { throw HelperError.rejected }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}
