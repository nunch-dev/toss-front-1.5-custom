import CryptoKit
import Darwin
import Foundation

struct HelperPolicy: Sendable {
    static let policyPath =
        "/Library/Security/SecurityAgentPlugins/PlfRemoteApproval.bundle/Contents/Resources/policy.json"
    static let keyPath = "/Library/Application Support/PLF02WHRemoteApproval/requester.private.json"
    static let screenKeyPath =
        "/Library/Application Support/PLF02WHRemoteApproval/screen-requester.private.json"
    static let caPath =
        "/Library/Security/SecurityAgentPlugins/PlfRemoteApproval.bundle/Contents/Resources/relay-ca.der"
    let mode: LocalApprovalMode
    let executionUID: uid_t
    let targetConsoleUID: uid_t?
    let relay: RelayPolicy
    let usesPrivateCA: Bool

    init(_ value: JSONValue) throws {
        let object = try value.object()
        try object.exact([
            "version", "mode", "executionUID", "targetConsoleUID", "relay",
            "requesterKeyFile", "caCertificateFile"
        ])
        let uid = try object.value("executionUID").seconds()
        guard try object.value("version").seconds() == 2,
              uid > 0, uid < Int64(uid_t.max),
              let mode = try LocalApprovalMode(rawValue: object.text("mode")) else {
            throw HelperError.rejected
        }
        self.mode = mode
        executionUID = uid_t(uid)
        relay = try RelayPolicy(object.value("relay"))
        switch mode {
        case .isolatedRightTest:
            guard case .null = try object.value("targetConsoleUID"),
                  relay.account == mode.rawValue,
                  try object.text("requesterKeyFile") == Self.keyPath else {
                throw HelperError.rejected
            }
            targetConsoleUID = nil
        case .screenTrial:
            let target = try object.value("targetConsoleUID").seconds()
            guard target > 0, target < Int64(uid_t.max),
                  relay.account == "screen-trial-uid-\(target)",
                  try object.text("requesterKeyFile") == Self.screenKeyPath else {
                throw HelperError.rejected
            }
            targetConsoleUID = uid_t(target)
        }
        switch try object.value("caCertificateFile") {
        case .null: usesPrivateCA = false
        case .string(let path) where path == Self.caPath: usesPrivateCA = true
        default: throw HelperError.rejected
        }
    }

    static func load() throws -> Self {
        let fd = plf_open_root_file(policyPath, 16_384)
        let policy = try Self(JSONValue.parse(TrustedData.consume(fd, maximumBytes: 16_384)))
        guard getuid() == policy.executionUID, geteuid() == policy.executionUID else {
            throw HelperError.rejected
        }
        return policy
    }

    func requesterKey() throws -> P256.Signing.PrivateKey {
        let path: String
        switch mode {
        case .isolatedRightTest: path = Self.keyPath
        case .screenTrial: path = Self.screenKeyPath
        }
        let fd = plf_open_private_file(path, executionUID, 4096)
        let key = try ApprovalProtocol.privateKey(
            JSONValue.parse(TrustedData.consume(fd, maximumBytes: 4096))
        )
        guard key.publicKey.x963Representation == relay.requesterKey.x963Representation else {
            throw HelperError.rejected
        }
        return key
    }

    func anchor() throws -> Data? {
        guard usesPrivateCA else { return nil }
        let fd = plf_open_root_file(Self.caPath, 16_384)
        let data = try TrustedData.consume(fd, maximumBytes: 16_384)
        guard !data.isEmpty else { throw HelperError.rejected }
        return data
    }
}
