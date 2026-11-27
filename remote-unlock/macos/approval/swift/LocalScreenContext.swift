import Foundation

enum LocalApprovalMode: String, Sendable {
    case isolatedRightTest = "isolated-right-test"
    case screenTrial = "screen-trial"

    static func screenUID(_ account: String) -> UInt32? {
        let prefix = "screen-trial-uid-"
        guard account.hasPrefix(prefix),
              let uid = UInt32(account.dropFirst(prefix.count)),
              uid > 0, uid < UInt32.max,
              account == "\(prefix)\(uid)" else { return nil }
        return uid
    }
}

// JSON types are parsed before passing observations to the shared C validator.
struct LocalScreenContext: Sendable {
    let executionUID: UInt32
    let callerSecuritySession: UInt32
    let attributes: UInt32
    let consoleUID: UInt32
    let cgUID: UInt32
    let onConsole: Bool
    let loginDone: Bool

    init(_ value: JSONValue) throws {
        let fields = try value.object()
        try fields.exact([
            "executionUID", "callerSecuritySession", "attributes",
            "consoleUID", "cgUID", "onConsole", "loginDone"
        ])
        func integer(_ name: String) throws -> UInt32 {
            let number = try fields.value(name).seconds()
            guard number <= Int64(UInt32.max) else { throw ProtocolErrorCode.invalidMessage }
            return UInt32(number)
        }
        executionUID = try integer("executionUID")
        callerSecuritySession = try integer("callerSecuritySession")
        attributes = try integer("attributes")
        consoleUID = try integer("consoleUID")
        cgUID = try integer("cgUID")
        guard case .bool(let console) = try fields.value("onConsole"),
              case .bool(let loggedIn) = try fields.value("loginDone") else {
            throw ProtocolErrorCode.invalidMessage
        }
        onConsole = console
        loginDone = loggedIn
        var context = observation
        guard PLFScreenContextValid(&context) else { throw ProtocolErrorCode.invalidMessage }
    }

    var observation: PLFScreenContext {
        PLFScreenContext(
            executionUID: executionUID, callerSecuritySession: callerSecuritySession,
            attributes: attributes, consoleUID: consoleUID, cgUID: cgUID,
            onConsole: onConsole, loginDone: loginDone
        )
    }

    var json: JSONValue {
        .object([
            "executionUID": .number(Double(executionUID)),
            "callerSecuritySession": .number(Double(callerSecuritySession)),
            "attributes": .number(Double(attributes)), "consoleUID": .number(Double(consoleUID)),
            "cgUID": .number(Double(cgUID)), "onConsole": .bool(onConsole),
            "loginDone": .bool(loginDone)
        ])
    }
}
