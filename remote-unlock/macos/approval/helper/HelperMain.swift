import Darwin
import Dispatch
import Foundation

@_cdecl("plf_helper_run")
func runApprovalHelper() {
    Task { @Sendable in await HelperMain.main() }
    dispatchMain()
}

enum HelperMain {
    static func main() async {
        do {
            let pipe = try HelperPipe()
            let invocation = try pipe.invocation()
            let cancellation = pipe.cancellationSource()
            defer { cancellation.cancel() }
            let policy = try HelperPolicy.load()
            let binding = try HelperContextBinding(policy: policy, invocation: invocation)
            let key = try policy.requesterKey()
            let anchor = try policy.anchor()
            let result = try await RelayClient.request(
                policy: policy.relay, key: key, invocation: invocation,
                anchorDER: anchor, bound: { @Sendable record in
                    try binding.check()
                    try pipe.emit(record)
                }
            )
            try binding.check()
            try pipe.emit(result)
            _exit(0)
        } catch HelperError.cancelled {
            _exit(2)
        } catch {
            plf_helper_fail()
        }
    }
}
