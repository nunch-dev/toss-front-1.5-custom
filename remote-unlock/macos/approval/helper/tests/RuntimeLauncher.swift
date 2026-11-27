import Darwin
import Dispatch
import Foundation

// TEST ONLY: Bun's stdio uses sockets on macOS. Foundation Pipe supplies the
// genuine FIFO descriptors required by the production HelperPipe boundary.
@main
enum RuntimeLauncher {
    static func copy(_ input: FileHandle, _ output: FileHandle) {
        do {
            var bytes = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(input.fileDescriptor, &bytes, bytes.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { _exit(1) }
                if count == 0 { break }
                try output.write(contentsOf: Data(bytes.prefix(count)))
            }
            try output.close()
        } catch { _exit(1) }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 4 else { _exit(1) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        child.arguments = Array(CommandLine.arguments.dropFirst(2))
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = errors
        try child.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        try errors.fileHandleForWriting.close()
        DispatchQueue.global().async {
            copy(.standardInput, input.fileHandleForWriting)
        }
        let drained = DispatchGroup()
        DispatchQueue.global().async(group: drained) {
            copy(output.fileHandleForReading, .standardOutput)
        }
        DispatchQueue.global().async(group: drained) {
            copy(errors.fileHandleForReading, .standardError)
        }
        child.waitUntilExit()
        drained.wait()
        _exit(child.terminationReason == .exit ? child.terminationStatus : 1)
    }
}
