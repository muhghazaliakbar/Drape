import Foundation

/// Runs a command-line tool and waits for it.
enum Command {
    struct Result: Sendable {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }
    }

    /// Runs off the main actor: `waitUntilExit` blocks its thread, and a
    /// `killall` or a Shortcut can take a noticeable moment to come back.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) async throws -> Result {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw GuardError.systemRefused("could not run \(launchPath)")
            }

            // Drain before waiting: a tool that fills the pipe buffer would
            // block forever if nobody is reading it.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return Result(
                status: process.terminationStatus,
                output: String(decoding: data, as: UTF8.self)
            )
        }.value
    }
}

/// The user's Shortcuts, as offered in the Focus picker.
enum ShortcutsCatalog {
    static func available() async -> [String] {
        guard let result = try? await Command.run("/usr/bin/shortcuts", ["list"]), result.succeeded else {
            return []
        }
        return result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
