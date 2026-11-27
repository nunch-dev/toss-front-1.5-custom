import Foundation

struct ProtocolMessage: Sendable {
    let payload: JSONValue
    let kind: String
    let issuer: String
    let audience: String
    let issuedAt: Int64
    let expiresAt: Int64
    let requestId: String?
    let requestHash: String?

    init(_ value: JSONValue) throws {
        let object = try value.object()
        kind = try object.text("kind")
        let common = ["version", "kind", "issuer", "audience", "issuedAt", "expiresAt"]
        switch kind {
        case "authenticate":
            try object.exact(common + ["nonce"])
            _ = try ProtocolFormat.decode64(object.text("nonce"), count: 32)
        case "request":
            try object.exact(common + ["requestId", "nonce", "account", "action"])
            try ProtocolFormat.uuid(object.text("requestId"))
            _ = try ProtocolFormat.decode64(object.text("nonce"), count: 32)
            guard try ProtocolFormat.matches(object.text("account"), "\\A[A-Za-z0-9_.-]{1,64}\\z"),
                  try object.text("action") == "screen-unlock" else {
                throw ProtocolErrorCode.invalidMessage
            }
        case "decision":
            try object.exact(common + ["requestId", "requestHash", "decision", "method"])
            try ProtocolFormat.uuid(object.text("requestId"))
            _ = try ProtocolFormat.decode64(object.text("requestHash"), count: 32)
            guard try ["approve", "deny"].contains(object.text("decision")),
                  try object.text("method") == "manual" else {
                throw ProtocolErrorCode.invalidMessage
            }
        default: throw ProtocolErrorCode.invalidMessage
        }
        guard try object.value("version").seconds() == 1 else {
            throw ProtocolErrorCode.invalidMessage
        }
        issuer = try object.text("issuer")
        audience = try object.text("audience")
        try ProtocolFormat.actor(issuer)
        try ProtocolFormat.actor(audience)
        issuedAt = try object.value("issuedAt").seconds()
        expiresAt = try object.value("expiresAt").seconds()
        requestId = try object["requestId"]?.string()
        requestHash = try object["requestHash"]?.string()
        payload = value
    }

    func checkTTL() throws {
        let ttl = expiresAt - issuedAt
        guard (1...60).contains(ttl) else { throw ProtocolErrorCode.invalidTTL }
    }

    func checkTime(now: Int64) throws {
        guard now >= 0, now <= 9_007_199_254_740_991 else {
            throw ProtocolErrorCode.invalidMessage
        }
        try checkTTL()
        guard issuedAt <= now + 5 else { throw ProtocolErrorCode.futureMessage }
        guard expiresAt > now else { throw ProtocolErrorCode.expired }
    }
}
