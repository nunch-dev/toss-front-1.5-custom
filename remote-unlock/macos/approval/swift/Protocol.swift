import CryptoKit
import Foundation

enum ApprovalProtocol {
    static let maximumTokenBytes = 16 * 1024

    static func publicKey(_ value: JSONValue) throws -> P256.Signing.PublicKey {
        let object = try value.object()
        try object.exact(["kty", "crv", "x", "y"])
        return try coordinates(object)
    }

    private static func coordinates(_ object: [String: JSONValue]) throws -> P256.Signing.PublicKey {
        guard try object.text("kty") == "EC", try object.text("crv") == "P-256" else {
            throw ProtocolErrorCode.invalidMessage
        }
        let x = try ProtocolFormat.decode64(object.text("x"), count: 32)
        let y = try ProtocolFormat.decode64(object.text("y"), count: 32)
        do { return try P256.Signing.PublicKey(x963Representation: Data([4]) + x + y) }
        catch { throw ProtocolErrorCode.invalidMessage }
    }

    static func privateKey(_ value: JSONValue) throws -> P256.Signing.PrivateKey {
        let object = try value.object()
        try object.exact(["kty", "crv", "x", "y", "d"])
        let suppliedPublic = try coordinates(object)
        let scalar = try ProtocolFormat.decode64(object.text("d"), count: 32)
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(rawRepresentation: scalar) }
        catch { throw ProtocolErrorCode.invalidMessage }
        guard key.publicKey.x963Representation == suppliedPublic.x963Representation else {
            throw ProtocolErrorCode.invalidMessage
        }
        return key
    }

    static func requestHash(_ originalToken: String) -> String {
        ProtocolFormat.base64url(Data(SHA256.hash(data: Data(originalToken.utf8))))
    }

    static func sign(_ message: ProtocolMessage, key: P256.Signing.PrivateKey) throws -> String {
        try message.checkTTL()
        let header = JSONValue.object([
            "alg": .string("ES256"), "typ": .string("remote-unlock+jws"),
            "kid": .string(message.issuer)
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let signingInput = try ProtocolFormat.base64url(encoder.encode(header)) + "."
            + ProtocolFormat.base64url(encoder.encode(message.payload))
        // CryptoKit's raw signature is the JWS 64-byte r || s representation.
        let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
        return signingInput + "." + ProtocolFormat.base64url(signature)
    }

    static func verify(
        _ token: String, key: P256.Signing.PublicKey,
        issuer: String, audience: String, now: Int64
    ) throws -> ProtocolMessage {
        guard token.utf8.count <= maximumTokenBytes else { throw ProtocolErrorCode.invalidToken }
        try ProtocolFormat.actor(issuer)
        try ProtocolFormat.actor(audience)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { throw ProtocolErrorCode.invalidSignature }
        let headerValue: JSONValue
        let payload: Data
        let signature: P256.Signing.ECDSASignature
        do {
            headerValue = try JSONValue.parse(ProtocolFormat.decode64(parts[0]))
            payload = try ProtocolFormat.decode64(parts[1])
            signature = try P256.Signing.ECDSASignature(
                rawRepresentation: ProtocolFormat.decode64(parts[2], count: 64)
            )
        } catch { throw ProtocolErrorCode.invalidSignature }
        // Verify the original compact bytes, never reconstructed JSON.
        guard key.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8)) else {
            throw ProtocolErrorCode.invalidSignature
        }
        do {
            let header = try headerValue.object()
            try header.exact(["alg", "typ", "kid"])
            guard try header.text("alg") == "ES256",
                  try header.text("typ") == "remote-unlock+jws",
                  try header.text("kid") == issuer else { throw ProtocolErrorCode.invalidHeader }
        } catch { throw ProtocolErrorCode.invalidHeader }
        let message = try ProtocolMessage(JSONValue.parse(payload))
        guard message.issuer == issuer, message.audience == audience else {
            throw ProtocolErrorCode.wrongTarget
        }
        try message.checkTime(now: now)
        return message
    }

    // The owner supplies an already verified request and its exact original JWS.
    // This checks binding only. The owner must enforce cancellation and consume once.
    static func verifyDecision(
        requestToken: String, request: ProtocolMessage, decisionToken: String,
        key: P256.Signing.PublicKey, now: Int64
    ) throws -> ProtocolMessage {
        guard request.kind == "request" else { throw ProtocolErrorCode.invalidMessage }
        try request.checkTTL()
        guard requestToken.utf8.count <= maximumTokenBytes else { throw ProtocolErrorCode.invalidToken }
        guard now >= 0, now <= 9_007_199_254_740_991 else {
            throw ProtocolErrorCode.invalidMessage
        }
        guard now < request.expiresAt else { throw ProtocolErrorCode.expired }
        let decision = try verify(
            decisionToken, key: key, issuer: request.audience, audience: request.issuer, now: now
        )
        guard decision.kind == "decision", decision.requestId == request.requestId,
              decision.requestHash == requestHash(requestToken),
              decision.expiresAt <= request.expiresAt else {
            throw ProtocolErrorCode.requestMismatch
        }
        return decision
    }
}
