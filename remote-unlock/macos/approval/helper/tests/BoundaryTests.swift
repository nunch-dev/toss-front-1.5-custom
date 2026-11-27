import CryptoKit
import Darwin
import Foundation

enum BoundaryFailure: Error { case assertion(String) }

@main
enum BoundaryTests {
    static func require(_ value: Bool, _ name: String) throws {
        guard value else { throw BoundaryFailure.assertion(name) }
    }

    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        var rejected = false
        do { try operation() } catch { rejected = true }
        try require(rejected, name)
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw BoundaryFailure.assertion("directory") }
        let directory = CommandLine.arguments[1]
        var path = Array((directory + "/bounded-data.XXXXXX").utf8CString)
        let fd = mkstemp(&path)
        try require(fd >= 0, "owned fixture creation")
        defer { close(fd); path.withUnsafeBufferPointer { _ = unlink($0.baseAddress) } }
        try require(write(fd, "fixture", 7) == 7, "fixture bytes")
        try require(lseek(fd, 0, SEEK_SET) == 0, "rewind fixture")
        let reader = dup(fd)
        let data = try TrustedData.consume(reader, maximumBytes: 7)
        try require(data == Data("fixture".utf8), "exact read bound accepted")
        try require(fcntl(reader, F_GETFD) == -1 && errno == EBADF, "success closes descriptor")
        var snapshot = stat()
        try require(fstat(fd, &snapshot) == 0 && snapshot.st_size == 7, "pre-growth snapshot")
        try require(pwrite(fd, "x", 1, 7) == 1, "grow after snapshot")
        try require(lseek(fd, 0, SEEK_SET) == 0, "rewind grown fixture")
        let overflowReader = dup(fd)
        try rejects("growth beyond bound rejected") {
            _ = try TrustedData.consume(overflowReader, maximumBytes: 7)
        }
        try require(fcntl(overflowReader, F_GETFD) == -1 && errno == EBADF, "failure closes descriptor")
        try rejects("invalid descriptor rejected") { _ = try TrustedData.consume(-1, maximumBytes: 7) }

        let coordinates = P256.Signing.PrivateKey().publicKey.x963Representation
        let key: JSONValue = .object([
            "kty": .string("EC"), "crv": .string("P-256"),
            "x": .string(ProtocolFormat.base64url(coordinates.subdata(in: 1..<33))),
            "y": .string(ProtocolFormat.base64url(coordinates.subdata(in: 33..<65)))
        ])
        let relay: JSONValue = .object([
            "relayURL": .string("wss://relay.example.test/v1/relay"),
            "relayId": .string("relay"), "requesterId": .string("requester"),
            "approverId": .string("approver"), "requesterPublicKey": key,
            "approverPublicKey": key, "account": .string("isolated-right-test")
        ])
        let fields: [String: JSONValue] = [
            "version": .number(2), "mode": .string("isolated-right-test"),
            "executionUID": .number(Double(getuid())), "targetConsoleUID": .null,
            "relay": relay, "requesterKeyFile": .string(HelperPolicy.keyPath),
            "caCertificateFile": .null
        ]
        let parsed = try HelperPolicy(.object(fields))
        try require(parsed.executionUID == getuid() && !parsed.usesPrivateCA, "fixed policy accepted")
        var anchored = fields
        anchored["caCertificateFile"] = .string(HelperPolicy.caPath)
        try require(try HelperPolicy(.object(anchored)).usesPrivateCA, "fixed CA accepted")
        let changes: [(String, JSONValue)] = [
            ("version", .bool(true)), ("version", .number(1)),
            ("executionUID", .number(0)), ("executionUID", .number(-1)),
            ("executionUID", .number(1.5)), ("executionUID", .number(Double(uid_t.max))),
            ("executionUID", .bool(true)), ("executionUID", .string("501")),
            ("requesterUID", .number(501)), ("targetConsoleUID", .number(501)),
            ("mode", .string("screen-trial")), ("mode", .bool(true)),
            ("requesterKeyFile", .string("/tmp/key")),
            ("caCertificateFile", .string("/tmp/ca.der")),
            ("caCertificateFile", .bool(false)), ("unknown", .null)
        ]
        for (field, value) in changes {
            var changed = fields
            changed[field] = value
            try rejects("strict policy \(field)") { _ = try HelperPolicy(.object(changed)) }
        }
        for field in fields.keys {
            var missing = fields
            missing.removeValue(forKey: field)
            try rejects("required policy \(field)") { _ = try HelperPolicy(.object(missing)) }
        }
        print("BOUNDARY_DATA_OK bounded growth, descriptor ownership, strict v2 policies")
    }
}
