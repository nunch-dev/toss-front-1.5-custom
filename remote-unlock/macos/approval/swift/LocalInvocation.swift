import Foundation

enum LocalInvocationTarget: Sendable {
    case isolated
    case screen(LocalScreenContext)

    var mode: LocalApprovalMode {
        switch self {
        case .isolated: .isolatedRightTest
        case .screen: .screenTrial
        }
    }

    var account: String {
        switch self {
        case .isolated: LocalApprovalMode.isolatedRightTest.rawValue
        case .screen(let context): "screen-trial-uid-\(context.consoleUID)"
        }
    }

    var context: JSONValue {
        switch self {
        case .isolated: .null
        case .screen(let context): context.json
        }
    }
}

struct ApprovalInvocation: Sendable {
    let target: LocalInvocationTarget
    let generation: String
    let requestId: String
    let nonce: String
    let issuedAt: Int64
    let expiresAt: Int64

    init(_ value: JSONValue) throws {
        let object = try value.object()
        try object.exact([
            "version", "mode", "account", "context", "generation",
            "requestId", "nonce", "issuedAt", "expiresAt"
        ])
        guard try object.value("version").seconds() == 2,
              let mode = try LocalApprovalMode(rawValue: object.text("mode")) else {
            throw ProtocolErrorCode.invalidMessage
        }
        switch mode {
        case .isolatedRightTest:
            guard case .null = try object.value("context") else {
                throw ProtocolErrorCode.invalidMessage
            }
            target = .isolated
        case .screenTrial:
            target = .screen(try LocalScreenContext(object.value("context")))
        }
        guard try object.text("account") == target.account else {
            throw ProtocolErrorCode.wrongTarget
        }
        generation = try object.text("generation")
        requestId = try object.text("requestId")
        nonce = try object.text("nonce")
        try ProtocolFormat.uuid(generation)
        try ProtocolFormat.uuid(requestId)
        _ = try ProtocolFormat.decode64(nonce, count: 32)
        issuedAt = try object.value("issuedAt").seconds()
        expiresAt = try object.value("expiresAt").seconds()
        guard (1...30).contains(expiresAt - issuedAt) else {
            throw ProtocolErrorCode.invalidTTL
        }
    }

    func request(policy: RelayPolicy) throws -> ProtocolMessage {
        guard target.account == policy.account else { throw ProtocolErrorCode.wrongTarget }
        return try ProtocolMessage(.object([
            "version": .number(1), "kind": .string("request"),
            "issuer": .string(policy.requester), "audience": .string(policy.approver),
            "issuedAt": .number(Double(issuedAt)), "expiresAt": .number(Double(expiresAt)),
            "requestId": .string(requestId), "nonce": .string(nonce),
            "account": .string(target.account), "action": .string("screen-unlock")
        ]))
    }

    // The four fields are the existing wire record API, shared with pipe callers.
    func record(kind: String, hash: String, expiresAt: Int64, decision: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "version": .number(2), "kind": .string(kind), "generation": .string(generation),
            "mode": .string(target.mode.rawValue), "account": .string(target.account),
            "context": target.context, "requestId": .string(requestId),
            "requestHash": .string(hash), "expiresAt": .number(Double(expiresAt))
        ]
        if let decision { fields["decision"] = .string(decision) }
        return .object(fields)
    }
}
