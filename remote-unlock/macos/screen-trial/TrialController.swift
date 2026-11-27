import Foundation
import Darwin

private let directory = URL(
    fileURLWithPath: "/Library/Application Support/PLF02WHRemoteApproval/screen-trial"
)

private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

private func trusted(_ url: URL) throws {
    var current = url
    while current.path != "/" {
        var info = stat()
        guard lstat(current.path, &info) == 0, info.st_uid == 0,
              info.st_mode & S_IFMT != S_IFLNK, info.st_mode & 0o022 == 0
        else { throw TrialError.unsafePath }
        current.deleteLastPathComponent()
    }
}

private func load(_ name: String) throws -> Data {
    let url = file(name)
    try trusted(url)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 16385) ?? Data()
    guard data.count <= 16384 else { throw TrialError.invalidState }
    return data
}

private func security(_ arguments: [String], input: String? = nil) throws -> Data {
    let process = Process()
    let output = Pipe()
    let finished = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["authorizationdb"] + arguments
    process.environment = ["PATH": "/usr/bin:/bin"]
    process.currentDirectoryURL = URL(fileURLWithPath: "/")
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    var inputHandle: FileHandle?
    if let input {
        try trusted(file(input))
        inputHandle = try FileHandle(forReadingFrom: file(input))
    }
    defer { try? inputHandle?.close() }
    process.standardInput = inputHandle ?? FileHandle.nullDevice
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + 10) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        throw TrialError.commandTimedOut
    }
    guard process.terminationStatus == 0 else {
        throw TrialError.commandFailed(process.terminationStatus)
    }
    return output.fileHandleForReading.readDataToEndOfFile()
}

private func currentRule() throws -> ScreenRule {
    try ScreenRule(security(["read", "system.login.screensaver"]))
}

private func restore() throws {
    let original = try ScreenRule(load("original.plist"))
    let trial = try ScreenRule(load("trial.plist"))
    guard try original.addingTrial().matches(trial) else { throw TrialError.invalidState }
    switch try currentRule().restoration(original: original, trial: trial) {
    case .unchanged:
        break
    case .restore:
        _ = try security(["write", "system.login.screensaver"], input: "original.plist")
        guard try currentRule().matches(original) else { throw TrialError.conflict }
    case .conflict:
        // Never overwrite a concurrent change made by another administrator.
        throw TrialError.conflict
    }
    try Data("RESTORED\n".utf8).write(to: file("restored"), options: .atomic)
    print("SCREEN_TRIAL_RESTORED")
}

@main
struct TrialController {
    static func main() {
        do {
            guard getuid() == 0, geteuid() == 0, CommandLine.arguments.count == 2 else {
                throw TrialError.invalidState
            }
            umask(0o022)
            try trusted(directory)
            let lock = open(file("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard lock >= 0 else { throw TrialError.unsafePath }
            defer { close(lock) }
            try trusted(file("lock"))
            guard flock(lock, LOCK_EX) == 0 else { throw TrialError.invalidState }
            defer { flock(lock, LOCK_UN) }
            switch CommandLine.arguments[1] {
            case "capture":
                let original = try currentRule()
                let trial = try original.addingTrial()
                try original.data.write(to: file("original.plist"), options: .withoutOverwriting)
                try trial.data.write(to: file("trial.plist"), options: .withoutOverwriting)
                print("SCREEN_TRIAL_CAPTURED")
            case "apply":
                guard !FileManager.default.fileExists(atPath: file("restored").path),
                      !FileManager.default.fileExists(atPath: file("deadline").path),
                      let heartbeat = Double(String(decoding: try load("ready"), as: UTF8.self)),
                      (0...15).contains(Date().timeIntervalSince1970 - heartbeat)
                else { throw TrialError.invalidState }
                let original = try ScreenRule(load("original.plist"))
                let trial = try ScreenRule(load("trial.plist"))
                guard try original.addingTrial().matches(trial),
                      try currentRule().matches(original) else { throw TrialError.conflict }
                // Persist the rollback deadline BEFORE mutating the system rule.
                let deadline = TrialDeadline(
                    wallTime: Date().timeIntervalSince1970,
                    uptime: ProcessInfo.processInfo.systemUptime
                )
                try JSONEncoder().encode(deadline).write(
                    to: file("deadline"), options: .withoutOverwriting
                )
                _ = try security(["write", "system.login.screensaver"], input: "trial.plist")
                guard try currentRule().matches(trial) else { throw TrialError.conflict }
                print("SCREEN_TRIAL_APPLIED expires=\(deadline.expiresAt)")
            case "check":
                if FileManager.default.fileExists(atPath: file("restored").path) { return }
                // RunAtLoad plus StartInterval also covers logout/reboot or loss of the agent.
                if FileManager.default.fileExists(atPath: file("deadline").path) {
                    let deadline = try JSONDecoder().decode(
                        TrialDeadline.self, from: load("deadline")
                    )
                    if deadline.elapsed(
                        wallTime: Date().timeIntervalSince1970,
                        uptime: ProcessInfo.processInfo.systemUptime
                    ) {
                        try restore()
                        return
                    }
                }
                try Data(String(Date().timeIntervalSince1970).utf8).write(
                    to: file("ready"), options: .atomic
                )
                print("SCREEN_TRIAL_WATCH_READY")
            case "restore":
                try restore()
            default:
                throw TrialError.invalidState
            }
        } catch {
            print("SCREEN_TRIAL_ERROR \(error)")
            exit(1)
        }
    }
}
