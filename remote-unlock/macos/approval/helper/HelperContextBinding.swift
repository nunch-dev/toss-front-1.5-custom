import Darwin

// The immutable invocation is rechecked at every externally visible boundary.
struct HelperContextBinding: Sendable {
    let policy: HelperPolicy
    let invocation: ApprovalInvocation

    init(policy: HelperPolicy, invocation: ApprovalInvocation) throws {
        self.policy = policy
        self.invocation = invocation
        try check()
    }

    func check() throws {
        guard getuid() == policy.executionUID, geteuid() == policy.executionUID,
              invocation.target.mode == policy.mode,
              invocation.target.account == policy.relay.account else {
            throw HelperError.rejected
        }
        switch invocation.target {
        case .isolated:
            guard policy.targetConsoleUID == nil else { throw HelperError.rejected }
        case .screen(let expected):
            guard expected.executionUID == policy.executionUID,
                  expected.consoleUID == policy.targetConsoleUID else {
                throw HelperError.rejected
            }
            var original = expected.observation
            var observed = PLFScreenContext()
            guard PLFCaptureScreenContext(&observed),
                  PLFScreenContextsEqual(&original, &observed) else {
                throw HelperError.rejected
            }
        }
    }
}
