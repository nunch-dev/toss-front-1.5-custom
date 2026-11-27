import Foundation

@main
struct ScreenRuleTests {
    static func main() throws {
        let original: [String: Any] = [
            "class": "rule", "k-of-n": 1, "version": 1,
            "rule": ["com.openai.sky.CUAService.AuthorizationPlugin.remote", "use-login-window-ui"],
            "comment": "Existing owner's policy", "created": 123.0, "modified": 456.0
        ]
        func rule(_ values: [String: Any]) throws -> ScreenRule {
            try ScreenRule(PropertyListSerialization.data(
                fromPropertyList: values, format: .xml, options: 0
            ))
        }
        func require(_ condition: Bool, _ name: String) {
            guard condition else { fatalError(name) }
            print("PASS \(name)")
        }
        let baseline = try rule(original)
        let trial = try baseline.addingTrial()
        require(trial.values["rule"] as? [String] == [
            "org.plf02wh.remoteunlock.screen-test",
            "com.openai.sky.CUAService.AuthorizationPlugin.remote",
            "use-login-window-ui"
        ], "preserves original fallback order while prepending the trial")
        require(trial.values["comment"] as? String == "Existing owner's policy",
                "preserves existing rule properties")
        require(trial.restoration(original: baseline, trial: trial) == .restore,
                "restores an unchanged trial definition")
        require(baseline.restoration(original: baseline, trial: trial) == .unchanged,
                "already restored definitions need no write")
        var changed = trial.values
        changed["rule"] = ["other-admin-rule", "use-login-window-ui"]
        require(try rule(changed).restoration(original: baseline, trial: trial) == .conflict,
                "does not overwrite another administrator's rule change")
        changed = trial.values
        changed["comment"] = "Another administrator changed policy"
        require(try rule(changed).restoration(original: baseline, trial: trial) == .conflict,
                "does not ignore non-timestamp changes")
        changed = trial.values
        changed["modified"] = 987.0
        require(try rule(changed).restoration(original: baseline, trial: trial) == .restore,
                "database-managed timestamps do not prevent restoration")
        do {
            _ = try trial.addingTrial()
            fatalError("duplicate trial accepted")
        } catch TrialError.alreadyInstalled { print("PASS duplicate trial rejected") }
        for invalid in [
            ["class": "allow"],
            ["class": "rule", "k-of-n": true, "rule": ["use-login-window-ui"]],
            ["class": "rule", "k-of-n": 2, "rule": ["use-login-window-ui"]],
            ["class": "rule", "k-of-n": 1, "rule": ["other-rule"]]
        ] {
            do {
                _ = try rule(invalid)
                fatalError("unsupported rule accepted")
            } catch TrialError.invalidRule { print("PASS unsupported rule rejected") }
        }
        let deadline = TrialDeadline(wallTime: 1000, uptime: 500)
        for (wallTime, uptime, expired, label) in [
            (1179.0, 679.0, false, "before deadline"),
            (1180.0, 680.0, true, "deadline boundary"),
            (900.0, 680.0, true, "wall-clock reversal"),
            (900.0, 10.0, true, "reboot"),
            (1200.0, 510.0, true, "wall-clock advance")
        ] {
            require(deadline.elapsed(wallTime: wallTime, uptime: uptime) == expired, label)
        }
        print("SCREEN_RULE_TESTS_OK")
    }
}
