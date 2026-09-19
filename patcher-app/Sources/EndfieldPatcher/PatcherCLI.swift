import Foundation

/// Headless mode: `Endfield Patcher.app/Contents/MacOS/EndfieldPatcher \
///     --patch /Applications/CrossOver.app /Applications/CrossOver-Endfield.app`
///
/// It exists so the patch sequence can be exercised (and scripted) without
/// clicking through the window — same code path as the GUI, same payload.
enum PatcherCLI {
    static let flag = "--patch"

    static func run(arguments: [String]) -> Int32 {
        guard arguments.count == 2 else {
            FileHandle.standardError.write(Data("""
            usage: EndfieldPatcher --patch <source CrossOver.app> <destination .app>

            The destination must not already exist.

            """.utf8))
            return 2
        }

        let source = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let destination = URL(fileURLWithPath: arguments[1]).standardizedFileURL

        guard let payloadDir = Payload.directory, Payload.isComplete else {
            fail("this build of the patcher does not include the Wine module payload")
            return 1
        }
        let info = CrossOverInfo(url: source)
        guard info.hasWineModules else {
            fail("\(source.path) does not look like a CrossOver installation")
            return 1
        }
        print("CrossOver \(info.version ?? "?") at \(source.path)")
        print("     ->  \(destination.path)\n")

        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do {
                try await PatcherEngine.performPatch(source: source, destination: destination,
                                                     payloadDir: payloadDir) { index, finished in
                    if !finished {
                        print("  • \(PatcherEngine.stepLabels[index])…")
                        fflush(stdout)
                    }
                }
            } catch {
                outcome.message = error.localizedDescription
            }
            done.signal()
        }
        done.wait()

        if let message = outcome.message {
            fail(message)
            return 1
        }
        print("\nDone. Right-click -> Open the first time, it is ad-hoc signed.")
        return 0
    }

    private final class Outcome: @unchecked Sendable {
        var message: String?
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("\nFAILED: \(message)\n".utf8))
    }
}
