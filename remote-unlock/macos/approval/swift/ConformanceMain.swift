import Foundation
import Darwin

// TEST ONLY: stdin fixtures, no credential access, IPC trust, or authorization callbacks.
@main
enum ConformanceMain {
    static func execute(_ input: JSONValue) throws -> JSONValue {
        let object = try input.object()
        switch try object.text("op") {
        case "verify":
            try object.exact(["op", "token", "publicKey", "issuer", "audience", "now"])
            let message = try ApprovalProtocol.verify(
                object.text("token"),
                key: ApprovalProtocol.publicKey(object.value("publicKey")),
                issuer: object.text("issuer"), audience: object.text("audience"),
                now: object.value("now").seconds()
            )
            return .object(["ok": .bool(true), "message": message.payload])
        case "sign":
            try object.exact(["op", "message", "privateKey"])
            let token = try ApprovalProtocol.sign(
                ProtocolMessage(object.value("message")),
                key: ApprovalProtocol.privateKey(object.value("privateKey"))
            )
            return .object(["ok": .bool(true), "token": .string(token)])
        case "verify-decision":
            try object.exact(["op", "requestToken", "request", "decisionToken", "publicKey", "now"])
            let message = try ApprovalProtocol.verifyDecision(
                requestToken: object.text("requestToken"),
                request: ProtocolMessage(object.value("request")),
                decisionToken: object.text("decisionToken"),
                key: ApprovalProtocol.publicKey(object.value("publicKey")),
                now: object.value("now").seconds()
            )
            return .object(["ok": .bool(true), "message": message.payload])
        default: throw ProtocolErrorCode.invalidMessage
        }
    }

    static func main() {
        do {
            let response: JSONValue
            do {
                var input = Data()
                while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
                    guard input.count + chunk.count <= 65_536 else {
                        throw ProtocolErrorCode.invalidMessage
                    }
                    input.append(chunk)
                }
                response = try execute(JSONValue.parse(input))
            } catch let error as ProtocolErrorCode {
                response = .object(["ok": .bool(false), "error": .string(error.rawValue)])
            }
            let output = try JSONEncoder().encode(response) + Data([10])
            try FileHandle.standardOutput.write(contentsOf: output)
        } catch {
            // Process faults disclose neither fixture keys nor tokens.
            let diagnostic = Data("protocol-conformance: process failure\n".utf8)
            try? FileHandle.standardError.write(contentsOf: diagnostic)
            exit(1)
        }
    }
}
