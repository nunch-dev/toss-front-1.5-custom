import CryptoKit
import Foundation

// Parses policy values only; the production loader must establish file ownership
// and code/configuration trust before creating this value.
struct RelayPolicy: Sendable {
    let url: URL
    let relay: String
    let requester: String
    let approver: String
    let requesterKey: P256.Signing.PublicKey
    let approverKey: P256.Signing.PublicKey
    let account: String

    init(_ value: JSONValue) throws {
        let object = try value.object()
        try object.exact([
            "relayURL", "relayId", "requesterId", "approverId",
            "requesterPublicKey", "approverPublicKey", "account"
        ])
        let address = try object.text("relayURL")
        guard let components = URLComponents(string: address),
              components.scheme == "wss", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path == "/v1/relay", let parsed = components.url else {
            throw RelayClientError.invalidPolicy
        }
        url = parsed
        relay = try object.text("relayId")
        requester = try object.text("requesterId")
        approver = try object.text("approverId")
        try ProtocolFormat.actor(relay)
        try ProtocolFormat.actor(requester)
        try ProtocolFormat.actor(approver)
        guard Set([relay, requester, approver]).count == 3 else {
            throw RelayClientError.invalidPolicy
        }
        requesterKey = try ApprovalProtocol.publicKey(object.value("requesterPublicKey"))
        approverKey = try ApprovalProtocol.publicKey(object.value("approverPublicKey"))
        account = try object.text("account")
        guard account == LocalApprovalMode.isolatedRightTest.rawValue ||
                LocalApprovalMode.screenUID(account) != nil else {
            throw RelayClientError.invalidPolicy
        }
    }
}

enum RelayClientError: String, Error {
    case invalidPolicy = "invalid_policy"
    case invalidPeer = "invalid_peer"
    case invalidPacket = "invalid_packet"
    case remoteRejected = "remote_rejected"
    case timeout
}
