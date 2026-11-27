import CryptoKit
import Darwin
import Foundation

enum ContextFailure: Error { case assertion(String) }

@main
enum ContextTests {
    static func require(_ value: Bool, _ name: String) throws {
        guard value else { throw ContextFailure.assertion(name) }
    }

    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch { return }
        throw ContextFailure.assertion(name)
    }

    static func main() throws {
        let context: [String: JSONValue] = [
            "executionUID": .number(Double(getuid())), "callerSecuritySession": .number(100023),
            "attributes": .number(8240), "consoleUID": .number(501), "cgUID": .number(501),
            "onConsole": .bool(true), "loginDone": .bool(true)
        ]
        let fields: [String: JSONValue] = [
            "version": .number(2), "mode": .string("screen-trial"),
            "account": .string("screen-trial-uid-501"), "context": .object(context),
            "generation": .string(UUID().uuidString), "requestId": .string(UUID().uuidString),
            "nonce": .string(ProtocolFormat.base64url(Data(repeating: 7, count: 32))),
            "issuedAt": .number(100), "expiresAt": .number(130)
        ]
        let invocation = try ApprovalInvocation(.object(fields))
        var echoed = try invocation.record(kind: "bound", hash: "hash", expiresAt: 130).object()
        try require(try echoed.value("version").seconds() == 2, "v2 record")
        try require(try echoed.text("mode") == "screen-trial", "screen mode echoed")
        try require(try echoed.text("account") == "screen-trial-uid-501", "screen account echoed")
        let echoedContext = try echoed.value("context").object()
        for field in context.keys {
            let expected = try JSONEncoder().encode(context[field])
            let actual = try JSONEncoder().encode(echoedContext[field])
            try require(expected == actual, "exact context echo \(field)")
        }
        echoed = try invocation.record(
            kind: "result", hash: "hash", expiresAt: 130, decision: "approve"
        ).object()
        try require(try echoed.value("context").object().count == context.count, "result context")

        let malformed: [(String, JSONValue)] = [
            ("executionUID", .number(0)), ("executionUID", .number(4294967295)),
            ("callerSecuritySession", .number(0)),
            ("callerSecuritySession", .number(4294967294)),
            ("attributes", .number(0)), ("attributes", .number(8241)),
            ("attributes", .number(8256)), ("attributes", .number(12336)),
            ("consoleUID", .number(0)),
            ("consoleUID", .number(4294967295)), ("cgUID", .number(502)),
            ("onConsole", .bool(false)), ("onConsole", .number(1)),
            ("loginDone", .bool(false)), ("loginDone", .string("true")),
            ("unknown", .number(1))
        ]
        for (field, value) in malformed {
            var changed = context
            changed[field] = value
            try rejects("invalid context \(field)") { _ = try LocalScreenContext(.object(changed)) }
        }
        for field in ["executionUID", "callerSecuritySession", "attributes", "consoleUID", "cgUID"] {
            for value: JSONValue in [.bool(true), .number(1.5), .number(-1), .number(4294967296), .null] {
                var changed = context
                changed[field] = value
                try rejects("strict numeric \(field)") { _ = try LocalScreenContext(.object(changed)) }
            }
        }
        for field in context.keys {
            var changed = context
            changed.removeValue(forKey: field)
            try rejects("required context \(field)") { _ = try LocalScreenContext(.object(changed)) }
        }
        var unknownBits = context
        unknownBits["attributes"] = .number(8240 + 0x40000000)
        _ = try LocalScreenContext(.object(unknownBits))
        for (field, value): (String, JSONValue) in [
            ("version", .number(1)), ("version", .bool(true)), ("mode", .string("unknown")),
            ("context", .null), ("context", .array([])), ("account", .string("screen-trial-uid-0501")),
            ("account", .string("screen-trial-uid-502")), ("unknown", .null)
        ] {
            var changed = fields
            changed[field] = value
            try rejects("strict invocation \(field)") { _ = try ApprovalInvocation(.object(changed)) }
        }
        for account in [
            "screen-trial-uid-0", "screen-trial-uid-4294967295", "screen-trial-uid-+501",
            "screen-trial-uid-0501", "screen-trial-uid-501.0", "screen-trial-uid-501\n"
        ] {
            try require(LocalApprovalMode.screenUID(account) == nil, "canonical account")
        }
        let coordinates = P256.Signing.PrivateKey().publicKey.x963Representation
        let key: JSONValue = .object([
            "kty": .string("EC"), "crv": .string("P-256"),
            "x": .string(ProtocolFormat.base64url(coordinates.subdata(in: 1..<33))),
            "y": .string(ProtocolFormat.base64url(coordinates.subdata(in: 33..<65)))
        ])
        let relay: [String: JSONValue] = [
            "relayURL": .string("wss://relay.example.test/v1/relay"),
            "relayId": .string("relay"), "requesterId": .string("requester"),
            "approverId": .string("approver"), "requesterPublicKey": key,
            "approverPublicKey": key, "account": .string("screen-trial-uid-501")
        ]
        let policy: [String: JSONValue] = [
            "version": .number(2), "mode": .string("screen-trial"),
            "executionUID": .number(Double(getuid())), "targetConsoleUID": .number(501),
            "relay": .object(relay), "requesterKeyFile": .string(HelperPolicy.screenKeyPath),
            "caCertificateFile": .null
        ]
        let parsed = try HelperPolicy(.object(policy))
        _ = try invocation.request(policy: parsed.relay)
        for (field, value): (String, JSONValue) in [
            ("targetConsoleUID", .null), ("targetConsoleUID", .bool(true)),
            ("targetConsoleUID", .number(0)), ("targetConsoleUID", .number(502)),
            ("targetConsoleUID", .number(4294967295)), ("targetConsoleUID", .number(1.5)),
            ("requesterKeyFile", .string(HelperPolicy.keyPath)), ("mode", .string("isolated-right-test"))
        ] {
            var changed = policy
            changed[field] = value
            try rejects("screen policy mapping \(field)") { _ = try HelperPolicy(.object(changed)) }
        }
        var isolatedRelay = relay
        isolatedRelay["account"] = .string("isolated-right-test")
        try rejects("request must match policy account") {
            _ = try invocation.request(policy: RelayPolicy(.object(isolatedRelay)))
        }
        var isolated = fields
        isolated["mode"] = .string("isolated-right-test")
        isolated["account"] = .string("isolated-right-test")
        try rejects("isolated context forbidden") { _ = try ApprovalInvocation(.object(isolated)) }
        isolated["context"] = .null
        _ = try ApprovalInvocation(.object(isolated))
        print("HELPER_CONTEXT_OK strict contexts, bounds, attributes, account and policy mapping")
    }
}
