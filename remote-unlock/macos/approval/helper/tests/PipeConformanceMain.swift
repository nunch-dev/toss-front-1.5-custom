import Darwin
import Dispatch
import Foundation

// TEST ONLY: exercises the production pipe boundary with synthetic records.
// Does not load policy, keys, or a relay; never install this executable.
@main
enum PipeConformanceMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        do {
            guard CommandLine.arguments.count == 2 else { throw HelperError.rejected }
            let pipe = try HelperPipe()
            let invocation = try pipe.invocation()
            let cancellation = pipe.cancellationSource()
            defer { cancellation.cancel() }
            let mode = CommandLine.arguments[1]
            let hash = ProtocolFormat.base64url(Data(repeating: 1, count: 32))
            let bound = invocation.record(kind: "bound", hash: hash, expiresAt: invocation.expiresAt)
            let result = invocation.record(
                kind: "result", hash: hash, expiresAt: invocation.expiresAt, decision: "deny"
            )
            switch mode {
            case "records", "third":
                try pipe.emit(bound)
                try pipe.emit(result)
                if mode == "third" { try pipe.emit(result) }
            case "wait":
                try pipe.emit(bound)
                dispatchMain()
            case "result-first": try pipe.emit(result)
            case "expired":
                try pipe.emit(invocation.record(kind: "bound", hash: hash, expiresAt: 0))
            case "oversized":
                var fields = try bound.object()
                fields["padding"] = .string(String(repeating: "x", count: 4096))
                try pipe.emit(.object(fields))
            default: throw HelperError.rejected
            }
            _exit(0)
        } catch HelperError.cancelled { _exit(2) }
        catch { _exit(1) }
    }
}
