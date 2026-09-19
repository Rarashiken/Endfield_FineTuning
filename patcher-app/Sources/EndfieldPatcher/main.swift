// AppKit entry point. Deliberately not SwiftUI: the SwiftUI macro plugins ship
// with full Xcode only, and this project builds with the Command Line Tools.
import AppKit

// Headless mode has to be handled before NSApplication is touched, otherwise the
// process tries to connect to the window server.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == PatcherCLI.flag {
    exit(PatcherCLI.run(arguments: Array(arguments.dropFirst())))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
