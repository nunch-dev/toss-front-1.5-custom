import CryptoKit
import Foundation

enum RelayClient {
    static func now() -> Int64 { Int64(Date().timeIntervalSince1970.rounded(.down)) }

    static func request(
        policy: RelayPolicy, key: P256.Signing.PrivateKey, invocation: ApprovalInvocation,
        anchorDER: Data? = nil,
        bound: @escaping @Sendable (JSONValue) throws -> Void
    ) async throws -> JSONValue {
        try Task.checkCancellation()
        guard key.publicKey.x963Representation == policy.requesterKey.x963Representation else {
            throw RelayClientError.invalidPeer
        }
        let request = try invocation.request(policy: policy)
        try request.checkTime(now: now())
        let token = try ApprovalProtocol.sign(request, key: key)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        let delegate = anchorDER.map { TLSAnchor(certificateDER: $0) }
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let socket = session.webSocketTask(with: policy.url)
        socket.maximumMessageSize = 17000
        socket.resume()
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }
        let remaining = min(30, request.expiresAt - now())
        guard remaining > 0 else { throw ProtocolErrorCode.expired }
        return try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await exchange(
                        socket: socket, policy: policy, key: key, invocation: invocation,
                        request: request, token: token, bound: bound
                    )
                } onCancel: {
                    socket.cancel(with: .goingAway, reason: nil)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(remaining))
                socket.cancel(with: .goingAway, reason: nil)
                throw RelayClientError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw RelayClientError.invalidPacket }
            return result
        }
    }

    private static func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: JSONValue] {
        let received = try await socket.receive()
        guard case .string(let text) = received, text.utf8.count <= 17000 else {
            throw RelayClientError.invalidPacket
        }
        let packet = try JSONValue.parse(Data(text.utf8)).object()
        if try packet.text("kind") == "error" {
            try packet.exact(["kind", "code"])
            guard try [
                "invalid_message", "not_allowed", "peer_offline", "busy",
                "no_pending_request", "expired", "cancelled", "duplicate_request"
            ].contains(packet.text("code")) else { throw RelayClientError.invalidPacket }
            throw RelayClientError.remoteRejected
        }
        return packet
    }

    private static func send(_ token: String, to socket: URLSessionWebSocketTask) async throws {
        let packet = JSONValue.object(["kind": .string("signed"), "token": .string(token)])
        let encoded = try JSONEncoder().encode(packet)
        try await socket.send(.string(String(decoding: encoded, as: UTF8.self)))
    }

    private static func exchange(
        socket: URLSessionWebSocketTask, policy: RelayPolicy, key: P256.Signing.PrivateKey,
        invocation: ApprovalInvocation, request: ProtocolMessage, token: String,
        bound: @escaping @Sendable (JSONValue) throws -> Void
    ) async throws -> JSONValue {
        let challenge = try await receive(socket)
        try challenge.exact(["kind", "relayId", "nonce", "expiresAt"])
        guard try challenge.text("kind") == "challenge",
              try challenge.text("relayId") == policy.relay else {
            throw RelayClientError.invalidPeer
        }
        let issuedAt = now()
        let authentication = try ProtocolMessage(.object([
            "version": .number(1), "kind": .string("authenticate"),
            "issuer": .string(policy.requester), "audience": .string(policy.relay),
            "issuedAt": .number(Double(issuedAt)),
            "expiresAt": .number(Double(min(issuedAt + 10, challenge.value("expiresAt").seconds()))),
            "nonce": challenge.value("nonce")
        ]))
        try await send(ApprovalProtocol.sign(authentication, key: key), to: socket)
        let acknowledgement = try await receive(socket)
        try acknowledgement.exact(["kind", "actor"])
        guard try acknowledgement.text("kind") == "authenticated",
              try acknowledgement.text("actor") == policy.requester else {
            throw RelayClientError.invalidPeer
        }
        try request.checkTime(now: now())
        try await send(token, to: socket)
        let hash = ApprovalProtocol.requestHash(token)
        try bound(invocation.record(kind: "bound", hash: hash, expiresAt: request.expiresAt))
        while true {
            let packet = try await receive(socket)
            switch try packet.text("kind") {
            case "submitted":
                try packet.exact(["kind", "requestId"])
                guard try packet.text("requestId") == invocation.requestId else {
                    throw RelayClientError.invalidPacket
                }
            case "signed":
                try packet.exact(["kind", "token"])
                let decision = try ApprovalProtocol.verifyDecision(
                    requestToken: token, request: request, decisionToken: packet.text("token"),
                    key: policy.approverKey, now: now()
                )
                try Task.checkCancellation()
                guard now() < min(request.expiresAt, decision.expiresAt) else {
                    throw ProtocolErrorCode.expired
                }
                return try invocation.record(
                    kind: "result", hash: hash, expiresAt: decision.expiresAt,
                    decision: decision.payload.object().text("decision")
                )
            default: throw RelayClientError.invalidPacket
            }
        }
    }
}
