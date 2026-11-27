import Foundation
import CoreFoundation

enum TrialError: Error {
    case invalidRule, alreadyInstalled, conflict, unsafePath, invalidState
    case commandFailed(Int32), commandTimedOut
}

struct ScreenRule {
    static let right = "org.plf02wh.remoteunlock.screen-test"
    let values: [String: Any]

    init(_ data: Data) throws {
        guard data.count <= 16384,
              let values = try PropertyListSerialization.propertyList(
                from: data, format: nil
              ) as? [String: Any],
              values["class"] as? String == "rule",
              let count = values["k-of-n"] as? NSNumber,
              CFGetTypeID(count) != CFBooleanGetTypeID(),
              count.intValue == 1, count.doubleValue == 1,
              let rules = values["rule"] as? [String],
              rules.contains("use-login-window-ui")
        else { throw TrialError.invalidRule }
        self.values = values
    }

    var data: Data {
        get throws {
            try PropertyListSerialization.data(
                fromPropertyList: values, format: .xml, options: 0
            )
        }
    }

    func addingTrial() throws -> ScreenRule {
        guard let rules = values["rule"] as? [String] else { throw TrialError.invalidRule }
        guard !rules.contains(Self.right) else { throw TrialError.alreadyInstalled }
        var result = values
        result["rule"] = [Self.right] + rules
        return try ScreenRule(PropertyListSerialization.data(
            fromPropertyList: result, format: .xml, options: 0
        ))
    }

    func matches(_ other: ScreenRule) -> Bool {
        var left = values
        var right = other.values
        // Authorization DB manages these timestamps when writing a definition.
        for key in ["created", "modified"] {
            left.removeValue(forKey: key)
            right.removeValue(forKey: key)
        }
        return NSDictionary(dictionary: left).isEqual(to: right)
    }

    enum Restoration { case unchanged, restore, conflict }

    func restoration(original: ScreenRule, trial: ScreenRule) -> Restoration {
        if matches(original) { return .unchanged }
        if matches(trial) { return .restore }
        return .conflict
    }
}
