import Foundation

/// Hardened wrapper around `Process` for the cleaner subsystem.
///
/// Rules enforced here:
/// - `launchPath` must be an absolute, executable file.
/// - Arguments are passed as `[String]`; **no shell** is ever invoked, so quoting
///   metacharacters cannot escape the argv boundary.
/// - The child process inherits no environment from the parent.
/// - A 5-second wall-clock timeout terminates the child if it hangs.
///
/// `CommandRunner` is **not** used for the AppleScript admin-escalation flow;
/// that path lives in `CleanupService` with its own dedicated validation because
/// the risk profile is different (it spawns a privileged shell).
enum CommandRunner {
    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var trimmedStdout: String {
            stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    enum RunError: Error {
        case launchPathMissing(String)
        case launchPathNotExecutable(String)
        case launchFailed(String)
        case timedOut
    }

    /// Resolves the first existing path among `candidates`. Returns nil if none exist.
    /// Used to find Homebrew across Apple Silicon (`/opt/homebrew/bin/brew`) and Intel
    /// (`/usr/local/bin/brew`) installs without invoking a shell.
    static func resolveBinary(_ candidates: [String]) -> String? {
        for path in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
               !isDir.boolValue,
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Synchronously runs `launchPath` with `arguments`. Returns captured stdout/stderr.
    /// Throws on launch failure or timeout.
    static func run(launchPath: String,
                    arguments: [String],
                    timeout: TimeInterval = 5) throws -> Output {
        guard launchPath.hasPrefix("/") else {
            throw RunError.launchPathMissing(launchPath)
        }
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            throw RunError.launchPathNotExecutable(launchPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = [:] // No inherited env — predictable behaviour.

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw RunError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                // Give the child a brief grace period before SIGKILL.
                Thread.sleep(forTimeInterval: 0.05)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw RunError.timedOut
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return Output(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
