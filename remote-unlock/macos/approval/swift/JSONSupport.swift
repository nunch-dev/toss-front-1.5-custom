import Foundation

enum ProtocolErrorCode: String, Error {
    case invalidToken = "invalid_token"
    case invalidHeader = "invalid_header"
    case invalidSignature = "invalid_signature"
    case invalidMessage = "invalid_message"
    case wrongTarget = "wrong_target"
    case invalidTTL = "invalid_ttl"
    case futureMessage = "future_message"
    case expired, cancelled, replayed
    case inProgress = "in_progress"
    case requestMismatch = "request_mismatch"
}

// Codable preserves JSON types without NSNumber's boolean/number coercions.
indirect enum JSONValue: Codable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    static func parse(_ data: Data) throws -> JSONValue {
        guard String(data: data, encoding: .utf8) != nil else {
            throw ProtocolErrorCode.invalidMessage
        }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw ProtocolErrorCode.invalidMessage }
    }

    func object() throws -> [String: JSONValue] {
        guard case .object(let value) = self else { throw ProtocolErrorCode.invalidMessage }
        return value
    }

    func string() throws -> String {
        guard case .string(let value) = self else { throw ProtocolErrorCode.invalidMessage }
        return value
    }

    func seconds() throws -> Int64 {
        // Zod's int() uses JavaScript's safe integer range.
        guard case .number(let value) = self, value.isFinite,
              value >= 0, value <= 9_007_199_254_740_991,
              value.rounded(.towardZero) == value else {
            throw ProtocolErrorCode.invalidMessage
        }
        return Int64(value)
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func exact(_ keys: [String]) throws {
        guard Set(self.keys) == Set(keys) else { throw ProtocolErrorCode.invalidMessage }
    }

    func value(_ key: String) throws -> JSONValue {
        guard let value = self[key] else { throw ProtocolErrorCode.invalidMessage }
        return value
    }

    func text(_ key: String) throws -> String { try value(key).string() }
}

enum ProtocolFormat {
    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    static func actor(_ value: String) throws {
        guard matches(value, "\\A[A-Za-z0-9_-]{1,64}\\z") else {
            throw ProtocolErrorCode.invalidMessage
        }
    }

    static func uuid(_ value: String) throws {
        let standard = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
        let maximum = "[fF]{8}-[fF]{4}-[fF]{4}-[fF]{4}-[fF]{12}"
        guard matches(value, "\\A(?:\(standard)|00000000-0000-0000-0000-000000000000|\(maximum))\\z") else {
            throw ProtocolErrorCode.invalidMessage
        }
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode64(_ value: String, count: Int? = nil) throws -> Data {
        guard matches(value, "\\A[A-Za-z0-9_-]+\\z"), value.utf8.count % 4 != 1 else {
            throw ProtocolErrorCode.invalidMessage
        }
        let padded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), base64url(data) == value,
              count == nil || data.count == count else {
            throw ProtocolErrorCode.invalidMessage
        }
        return data
    }
}
