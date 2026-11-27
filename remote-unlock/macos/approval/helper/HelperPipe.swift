import Darwin
import Dispatch
import Foundation

// Only emitted is mutable shared state, protected by lock. Descriptors are
// inherited dedicated pipes. The owner must still arbitrate cancellation
// against a result already in transit on stdout.
final class HelperPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var emitted = 0
    private let deadline = DispatchTime.now() + .seconds(30)
    private let watchdog: DispatchSourceTimer

    init() throws {
        for descriptor in [STDIN_FILENO, STDOUT_FILENO] {
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFIFO else { throw HelperError.rejected }
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw HelperError.rejected
            }
        }
        watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        watchdog.schedule(deadline: deadline)
        watchdog.setEventHandler { @Sendable in _exit(2) }
        watchdog.resume()
    }

    deinit { watchdog.cancel() }

    func invocation() throws -> ApprovalInvocation {
        var data = Data()
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline.uptimeNanoseconds else { throw HelperError.cancelled }
            let remaining = (deadline.uptimeNanoseconds - now) / 1_000_000
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(max(1, remaining)))
            if ready < 0 && errno == EINTR { continue }
            if ready == 0 { throw HelperError.cancelled }
            guard ready > 0 else { throw HelperError.rejected }
            var byte: UInt8 = 0
            let count = read(STDIN_FILENO, &byte, 1)
            if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            if count == 0 { throw HelperError.cancelled }
            guard count == 1 else { throw HelperError.rejected }
            if byte == 10 {
                try checkLive()
                return try ApprovalInvocation(JSONValue.parse(data))
            }
            // The newline is included in the 4096-byte record limit.
            guard data.count < 4095 else { throw HelperError.rejected }
            data.append(byte)
        }
    }

    func cancellationSource() -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: STDIN_FILENO, queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { @Sendable [self] in
            lock.withLock {
                do { try checkLive() }
                catch { _exit(2) }
            }
        }
        source.resume()
        return source
    }

    private func checkLive() throws {
        guard DispatchTime.now() < deadline else { throw HelperError.cancelled }
        var byte: UInt8 = 0
        while true {
            let count = read(STDIN_FILENO, &byte, 1)
            if count < 0 && errno == EINTR { continue }
            if count >= 0 { throw HelperError.cancelled }
            guard errno == EAGAIN else { throw HelperError.rejected }
            return
        }
    }

    func emit(_ record: JSONValue) throws {
        try lock.withLock {
            try checkLive()
            let fields = try record.object()
            guard emitted < 2,
                  try fields.text("kind") == (emitted == 0 ? "bound" : "result"),
                  try fields.value("expiresAt").seconds() > RelayClient.now() else {
                throw HelperError.rejected
            }
            let data = try JSONEncoder().encode(record) + Data([10])
            guard data.count <= 4096 else { throw HelperError.rejected }
            let written = data.withUnsafeBytes { bytes in
                Darwin.write(STDOUT_FILENO, bytes.baseAddress, bytes.count)
            }
            guard written == data.count else { throw HelperError.rejected }
            emitted += 1
        }
    }
}
