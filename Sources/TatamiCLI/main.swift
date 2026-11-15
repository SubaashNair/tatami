import Foundation
import TatamiCore

// `tatami`: sends one command to the running Tatami app over its private local socket and prints the answer.
// Exit codes: 0 done, 1 the app refused or failed, 2 bad usage, 3 Tatami is not running or the command is off, 4 no usable reply.

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard let first = arguments.first?.lowercased() else { fail(CLICommand.helpText, code: 2) }
if ["help", "--help", "-h"].contains(first) { print(CLICommand.helpText); exit(0) }

// Check the words here too, so a typo is reported even when the app is not running.
switch CLICommand.parse(arguments) {
case .failure(.unknown(let name)): fail("Unknown command \"\(name)\". Run: tatami help", code: 2)
case .failure(.usage(let text)): fail(text, code: 2)
case .failure(.empty): fail(CLICommand.helpText, code: 2)
case .success: break
}

let socketPath = CLIPaths.socketPath(home: NSHomeDirectory(), uid: getuid())
do {
    let response = try CLIClient.send(CLIRequest(args: arguments), path: socketPath)
    guard response.ok else { fail(CLIFormat.cleanLines(response.error ?? "The command failed."), code: 1) }
    if !response.output.isEmpty { print(CLIFormat.cleanLines(response.output)) }
} catch CLIClientError.notRunning {
    fail("Tatami is not running, or command-line control is off. Start Tatami, or turn on \"Allow command-line control\" in Preferences.", code: 3)
} catch CLIClientError.timedOut {
    fail("Tatami did not answer in time.", code: 4)
} catch CLIClientError.tooLarge {
    fail("Tatami's reply was too large to read.", code: 4)
} catch {
    fail("Tatami sent a reply this command does not understand. Update the app and the command to the same release.", code: 4)
}
