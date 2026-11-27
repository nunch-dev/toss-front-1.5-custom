import Darwin
import Dispatch
import Foundation

// TEST ONLY. Policy and ephemeral test key arrive on stdin. This executable is
// not a trusted production helper and must never be installed as one.
@main
enum RequestorConformanceMain {
    static func inputLine() throws -> Data {
        var data = Data()
        while true {
            var byte: UInt8 = 0
            let count = read(STDIN_FILENO, &byte, 1)
            if count < 0 && errno == EINTR { continue }
            guard count == 1 else { throw ProtocolErrorCode.invalidMessage }
            if byte == 10 { return data }
            guard data.count < 65_536 else { throw ProtocolErrorCode.invalidMessage }
            data.append(byte)
        }
    }

    static func emit(_ value: JSONValue) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 4096 else { throw RelayClientError.invalidPacket }
        try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
    }

    static func main() async {
        do {
            let input = try JSONValue.parse(inputLine()).object()
            try input.exact(["policy", "privateKey", "invocation", "caCertificateDER"])
            let policy = try RelayPolicy(input.value("policy"))
            let invocation = try ApprovalInvocation(input.value("invocation"))
            let key = try ApprovalProtocol.privateKey(input.value("privateKey"))
            let anchor: Data?
            switch try input.value("caCertificateDER") {
            case .null: anchor = nil
            case .string(let encoded):
                guard let decoded = Data(base64Encoded: encoded),
                      !decoded.isEmpty, decoded.count <= 16_384 else {
                    throw RelayClientError.invalidPolicy
                }
                anchor = decoded
            default: throw RelayClientError.invalidPolicy
            }
            let flags = fcntl(STDIN_FILENO, F_GETFL)
            guard flags >= 0, fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw RelayClientError.invalidPacket
            }
            let control = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .global())
            control.setEventHandler { @Sendable in
                var byte: UInt8 = 0
                let count = read(STDIN_FILENO, &byte, 1)
                if count >= 0 || (errno != EAGAIN && errno != EINTR) {
                    exit(2)
                }
            }
            control.resume()
            defer { control.cancel() }
            let result = try await RelayClient.request(
                policy: policy, key: key, invocation: invocation, anchorDER: anchor, bound: emit
            )
            try emit(result)
        } catch let error as ProtocolErrorCode {
            fail(error.rawValue)
        } catch let error as RelayClientError {
            fail(error.rawValue)
        } catch {
            fail("transport_or_process_failure")
        }
    }

    static func fail(_ code: String) -> Never {
        try? FileHandle.standardError.write(contentsOf: Data("REQUESTOR_FAILED \(code)\n".utf8))
        exit(1)
    }
}
