import Darwin
import Dispatch
import Foundation

enum PipeFailure: Error { case assertion(String) }

final class Child {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()

    init(executable: String, arguments: [String], environment: [String: String] = [:]) throws {
        // Foundation Process injects __CF_USER_TEXT_ENCODING even for [:].
        // env -i supplies the same empty exec environment the C owner will use.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["-i"] + environment.map { "\($0.key)=\($0.value)" } + [executable] + arguments
        process.environment = [:]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        try errors.fileHandleForWriting.close()
    }

    func send(_ data: Data) throws { try input.fileHandleForWriting.write(contentsOf: data) }

    func line() throws -> Data {
        var data = Data()
        while data.count <= 4096 {
            guard let byte = try output.fileHandleForReading.read(upToCount: 1), byte.count == 1 else {
                throw PipeFailure.assertion("missing bounded output line")
            }
            data.append(byte)
            if byte[0] == 10 { return data }
        }
        throw PipeFailure.assertion("unbounded output line")
    }

    func finish(_ expected: Int32, budget: Int = 5) throws -> Data {
        let started = DispatchTime.now().uptimeNanoseconds
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + .seconds(budget))
        timer.setEventHandler { @Sendable [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        timer.resume()
        defer { timer.cancel() }
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == expected else {
            let diagnostic = try errors.fileHandleForReading.readToEnd() ?? Data()
            try FileHandle.standardError.write(contentsOf: diagnostic)
            let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            throw PipeFailure.assertion("exit \(process.terminationStatus), expected \(expected), after \(elapsed) ms")
        }
        return data
    }
}

@main
enum PipeTests {
    static func require(_ value: Bool, _ name: String) throws {
        guard value else { throw PipeFailure.assertion(name) }
    }

    static func invocation() throws -> Data {
        let now = Int64(Date().timeIntervalSince1970)
        let fields: [String: JSONValue] = [
            "version": .number(2), "mode": .string("isolated-right-test"),
            "account": .string("isolated-right-test"), "context": .null,
            "generation": .string(UUID().uuidString),
            "requestId": .string(UUID().uuidString),
            "nonce": .string(ProtocolFormat.base64url(Data(repeating: 7, count: 32))),
            "issuedAt": .number(Double(now)), "expiresAt": .number(Double(now + 30))
        ]
        return try JSONEncoder().encode(JSONValue.object(fields)) + Data([10])
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw PipeFailure.assertion("output directory") }
        let directory = CommandLine.arguments[1]
        let probe = directory + "/helper-pipe-conformance"
        let helper = directory + "/approval-helper"
        let records = try Child(executable: probe, arguments: ["records"])
        try records.send(invocation())
        let valid = try records.finish(0)
        let lines = valid.split(separator: 10)
        try require(lines.count == 2 && lines.allSatisfy { $0.count < 4096 }, "two bounded records")
        try require(try JSONValue.parse(Data(lines[0])).object().text("kind") == "bound", "bound first")
        try require(try JSONValue.parse(Data(lines[1])).object().text("decision") == "deny", "result second")

        for mode in ["result-first", "expired", "oversized"] {
            let child = try Child(executable: probe, arguments: [mode])
            try child.send(invocation())
            try require(try child.finish(1).isEmpty, "\(mode) rejected before output")
        }
        let third = try Child(executable: probe, arguments: ["third"])
        try third.send(invocation())
        try require(try third.finish(1).split(separator: 10).count == 2, "third record refused")
        for extra in [false, true] {
            let child = try Child(executable: probe, arguments: ["wait"])
            try child.send(invocation())
            _ = try child.line() // Subscribe by observing bound before cancelling.
            if extra { try child.send(Data([32])) }
            else { try child.input.fileHandleForWriting.close() }
            try require(try child.finish(2).isEmpty, "EOF/additional byte cancels after bound")
        }
        for invalid in [Data("{}".utf8) + Data([10]), Data(repeating: 32, count: 4096) + Data([10])] {
            let child = try Child(executable: probe, arguments: ["records"])
            try child.send(invalid)
            try require(try child.finish(1).isEmpty, "invalid or oversized invocation rejected")
        }
        let earlyEOF = try Child(executable: helper, arguments: [])
        try earlyEOF.input.fileHandleForWriting.close()
        try require(try earlyEOF.finish(2).isEmpty, "EOF before invocation cancels")
        let extraInput = try Child(executable: probe, arguments: ["records"])
        try extraInput.send(invocation() + Data([32]))
        try require(try extraInput.finish(2).isEmpty, "buffered extra input cancels before output")
        let deadline = try Child(executable: helper, arguments: [])
        try deadline.send(Data("{".utf8))
        try require(try deadline.finish(2, budget: 35).isEmpty, "clean production launch waits for invocation then times out")

        let argument = try Child(executable: helper, arguments: ["--policy=/tmp/policy"])
        try require(try argument.finish(1).isEmpty, "production argument override rejected")
        let environment = try Child(
            executable: helper, arguments: [], environment: ["PLF_POLICY": "/tmp/policy"]
        )
        try require(try environment.finish(1).isEmpty, "production environment override rejected")
        let malformed = try Child(executable: helper, arguments: [])
        try malformed.send(Data("{}\n".utf8))
        try require(try malformed.finish(1).isEmpty, "production rejects malformed invocation")
        let diagnostic = try malformed.errors.fileHandleForReading.readToEnd()
        try require(diagnostic == Data("APPROVAL_HELPER_FAILED\n".utf8), "generic nonsecret diagnostic")
        print("HELPER_PIPE_OK 15 scenarios including 30 second startup deadline")
    }
}
