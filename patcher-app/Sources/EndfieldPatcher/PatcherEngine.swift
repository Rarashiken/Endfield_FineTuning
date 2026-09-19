import Foundation

struct PatchError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One patched Wine module: where it lives in the app's bundled payload and
/// where it goes inside a CrossOver.app copy.
struct PayloadModule {
    let payloadSubpath: String    // relative to Resources/payload/
    let crossoverSubpath: String  // relative to Contents/SharedSupport/CrossOver/
}

enum Payload {
    static let modules: [PayloadModule] = [
        // Rosetta NOP + privileged-instruction fixes, NtDelayExecution QPC timing
        PayloadModule(payloadSubpath: "x86_64-unix/ntdll.so",
                      crossoverSubpath: "lib/wine/x86_64-unix/ntdll.so"),
        // KiUser*Dispatcher int3 spoof
        PayloadModule(payloadSubpath: "x86_64-windows/kernel32.dll",
                      crossoverSubpath: "lib/wine/x86_64-windows/kernel32.dll"),
        // ntoskrnl.exe em-backports, plus PsGetProcessExitStatus implemented
        PayloadModule(payloadSubpath: "x86_64-windows/ntoskrnl.exe",
                      crossoverSubpath: "lib/wine/x86_64-windows/ntoskrnl.exe"),
        // winebus: DualSense reported like it is on Windows (no XInput marker,
        // native HID layout), and instance IDs without disallowed characters
        PayloadModule(payloadSubpath: "x86_64-unix/winebus.so",
                      crossoverSubpath: "lib/wine/x86_64-unix/winebus.so"),
        PayloadModule(payloadSubpath: "x86_64-windows/winebus.sys",
                      crossoverSubpath: "lib/wine/x86_64-windows/winebus.sys"),
    ]

    /// The rpath the payload ntdll.so must carry so CrossOver's cxcompatdb.so
    /// (and through it D3DMetal) keeps working. Added at app-build time by
    /// scripts/build-app.sh so end users never need Xcode tools.
    static let requiredNtdllRpath = "@loader_path/../../../lib64"

    /// winebus.so dlopens libSDL2 from CrossOver's lib64; without these rpaths the
    /// SDL backend silently fails and no controller appears. Also baked in at
    /// app-build time.
    static let requiredWinebusRpaths = ["@loader_path/../lib64", "@loader_path/../../../lib64"]

    /// Directory containing the bundled pre-built modules.
    /// FINETUNING_PAYLOAD_DIR overrides it for development (`swift run`).
    static var directory: URL? {
        if let override = ProcessInfo.processInfo.environment["FINETUNING_PAYLOAD_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("payload", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var isComplete: Bool {
        guard let dir = directory else { return false }
        return modules.allSatisfy {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.payloadSubpath).path)
        }
    }
}

/// What we know about a selected CrossOver.app.
struct CrossOverInfo {
    static let expectedVersion = "26.3"

    let url: URL
    let version: String?
    let bundleIdentifier: String?
    let hasWineModules: Bool

    var isExpectedVersion: Bool { version?.hasPrefix(Self.expectedVersion) == true }
    var displayName: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL) {
        self.url = url
        var plist: [String: Any] = [:]
        if let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
           let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            plist = parsed
        }
        version = plist["CFBundleShortVersionString"] as? String
        bundleIdentifier = plist["CFBundleIdentifier"] as? String
        let cxr = url.appendingPathComponent("Contents/SharedSupport/CrossOver")
        hasWineModules = Payload.modules.allSatisfy {
            FileManager.default.fileExists(atPath: cxr.appendingPathComponent($0.crossoverSubpath).path)
        }
    }
}

/// Performs the patch. Mirrors scripts/swap-into-crossover.sh steps 1, 2 and 5
/// (the Wine-module swap). GPTK4/MoltenVK graphics upgrades are intentionally
/// out of scope — Apple's GPTK may not be redistributed.
/// A mutable box so the detached task can record which step was running when a
/// failure came back out of `performPatch`.
private final class Counter: @unchecked Sendable {
    var value = 0
}

@MainActor
final class PatcherEngine {
    struct Step: Identifiable {
        enum Status { case pending, running, done, failed }
        let id: Int
        let label: String
        var status: Status = .pending
    }

    /// Called on the main actor whenever `steps`, `isRunning`, `patchedApp`
    /// or `errorMessage` changes. Set by the UI layer.
    var onChange: (() -> Void)?

    private(set) var steps: [Step] = [] { didSet { onChange?() } }
    private(set) var isRunning = false { didSet { onChange?() } }
    private(set) var patchedApp: URL? { didSet { onChange?() } }
    var errorMessage: String? { didSet { onChange?() } }

    nonisolated static let stepLabels = [
        "Copying CrossOver",
        "Installing the patched Wine modules",
        "Giving the copy its own bundle identifier",
        "Re-signing and clearing quarantine",
        "Verifying",
    ]

    func reset() {
        steps = []
        patchedApp = nil
        errorMessage = nil
    }

    func patch(source: URL, destination: URL) {
        guard !isRunning else { return }
        guard let payloadDir = Payload.directory, Payload.isComplete else {
            errorMessage = "This build of the patcher does not include the Wine module payload. Rebuild it with patcher-app/scripts/build-app.sh after scripts/build-wine.sh all."
            return
        }
        reset()
        isRunning = true
        steps = Self.stepLabels.enumerated().map { Step(id: $0.offset, label: $0.element) }

        Task.detached(priority: .userInitiated) {
            let current = Counter()
            do {
                try await Self.performPatch(source: source, destination: destination,
                                            payloadDir: payloadDir) { index, finished in
                    if !finished { current.value = index }
                    await MainActor.run { self.steps[index].status = finished ? .done : .running }
                }
                await MainActor.run {
                    self.patchedApp = destination
                    self.isRunning = false
                }
            } catch {
                let failed = current.value
                await MainActor.run {
                    self.steps[failed].status = .failed
                    self.errorMessage = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    // MARK: - Workers (run off the main actor)

    /// The patch sequence itself. The GUI and the headless `--patch` mode both
    /// go through here, so what gets tested on the command line is exactly what
    /// runs when the button is pressed. `progress` is called with the step index
    /// and false before a step, true after it.
    nonisolated static func performPatch(source: URL, destination: URL, payloadDir: URL,
                                         progress: (Int, Bool) async -> Void) async throws {
        let stages: [() throws -> Void] = [
            { try copyBundle(from: source, to: destination) },
            { try installModules(into: destination, from: payloadDir) },
            { try assignBundleIdentifier(destination) },
            { try resignAndClearQuarantine(destination) },
            { try verify(destination, payloadDir: payloadDir) },
        ]
        for (index, stage) in stages.enumerated() {
            await progress(index, false)
            try stage()
            await progress(index, true)
        }
    }

    private nonisolated static func cxRoot(_ app: URL) -> URL {
        app.appendingPathComponent("Contents/SharedSupport/CrossOver", isDirectory: true)
    }

    private nonisolated static func copyBundle(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let src = source.standardizedFileURL
        let dst = destination.standardizedFileURL
        guard dst.pathExtension == "app" else {
            throw PatchError("The destination must be an .app path.")
        }
        guard src.path != dst.path else {
            throw PatchError("The destination must be different from the original CrossOver.app.")
        }
        guard !dst.path.hasPrefix(src.path + "/"), !src.path.hasPrefix(dst.path + "/") else {
            throw PatchError("The destination cannot be inside the original CrossOver.app (or vice versa).")
        }
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        // ditto, not `cp -a`: scripts/make-endfield-crossover.sh records that cp -a
        // produced an incomplete bundle here (files missing). ditto is what the
        // verified path uses, and it preserves resource forks and ACLs too.
        try run("/usr/bin/ditto", [src.path, dst.path])
    }

    private nonisolated static func installModules(into app: URL, from payloadDir: URL) throws {
        let fm = FileManager.default
        let cxr = cxRoot(app)
        for module in Payload.modules {
            let src = payloadDir.appendingPathComponent(module.payloadSubpath)
            let dst = cxr.appendingPathComponent(module.crossoverSubpath)
            guard fm.fileExists(atPath: src.path) else {
                throw PatchError("The bundled payload is missing \(module.payloadSubpath).")
            }
            guard fm.fileExists(atPath: dst.path) else {
                throw PatchError("\(module.crossoverSubpath) not found in the copied app — is this really CrossOver \(CrossOverInfo.expectedVersion)?")
            }
            // Keep a backup of the stock module under the same name the shell script uses.
            let backup = dst.appendingPathExtension("cxorig")
            if !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: dst, to: backup)
            }
            try fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
            // Ad-hoc signature so the modified file loads on Apple Silicon. For the
            // PE modules codesign stores it in xattrs; harmless and matches the script.
            try run("/usr/bin/codesign", ["--force", "--sign", "-", dst.path])
        }
    }

    /// Two copies of CrossOver sharing one CFBundleIdentifier make LaunchServices
    /// pick whichever it saw last, which shows up as the wrong app launching or as
    /// a "damaged" dialog. Derive a unique identifier from the destination name.
    private nonisolated static func assignBundleIdentifier(_ app: URL) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let name = app.deletingPathExtension().lastPathComponent
        let suffix = name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                         .reduce(into: "") { $0.unicodeScalars.append($1) }
        guard !suffix.isEmpty else { return }
        try run("/usr/libexec/PlistBuddy",
                ["-c", "Set :CFBundleIdentifier com.codeweavers.CrossOver.\(suffix)", plist.path])
    }

    /// Re-sign rather than strip the seal. Removing _CodeSignature leaves an invalid
    /// signature, which recent macOS reports as a damaged application. Entitlements
    /// are carried over from the original, and --deep is deliberately not used.
    private nonisolated static func resignAndClearQuarantine(_ app: URL) throws {
        _ = try? run("/usr/bin/xattr", ["-drs", "com.apple.quarantine", app.path])

        let entitlements = FileManager.default.temporaryDirectory
            .appendingPathComponent("endfield-patcher-entitlements-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: entitlements) }

        var args = ["--force", "--sign", "-"]
        if let dumped = try? run("/usr/bin/codesign", ["-d", "--entitlements", ":-", app.path]),
           let start = dumped.range(of: "<?xml"),
           (try? String(dumped[start.lowerBound...])
                .write(to: entitlements, atomically: true, encoding: .utf8)) != nil {
            args += ["--entitlements", entitlements.path]
        }
        args.append(app.path)
        try run("/usr/bin/codesign", args)
        try run("/usr/bin/codesign", ["--verify", app.path])
    }

    private nonisolated static func verify(_ app: URL, payloadDir: URL) throws {
        let cxr = cxRoot(app)
        for module in Payload.modules {
            let src = payloadDir.appendingPathComponent(module.payloadSubpath)
            let dst = cxr.appendingPathComponent(module.crossoverSubpath)
            guard let a = fileSize(src), let b = fileSize(dst), a == b else {
                throw PatchError("\(module.crossoverSubpath) does not match the bundled payload after the swap.")
            }
        }
        // ntdll.so is the module the kernel actually checks; make sure its ad-hoc
        // signature is valid and that it carries the lib64 rpath (baked in at
        // app-build time) — without that rpath cxcompatdb.so can't load and
        // D3DMetal never engages.
        let ntdll = cxr.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")
        try run("/usr/bin/codesign", ["--verify", ntdll.path])
        let data = try Data(contentsOf: ntdll, options: .alwaysMapped)
        guard let needle = Payload.requiredNtdllRpath.data(using: .utf8),
              data.range(of: needle) != nil else {
            throw PatchError("ntdll.so is missing the lib64 rpath — D3DMetal would not work. Rebuild the patcher with scripts/build-app.sh (it adds the rpath to the payload).")
        }

        // winebus.so dlopens libSDL2 by leaf name out of CrossOver's lib64. Miss
        // these rpaths and the SDL backend fails silently: no controller at all.
        let winebus = cxr.appendingPathComponent("lib/wine/x86_64-unix/winebus.so")
        try run("/usr/bin/codesign", ["--verify", winebus.path])
        let busData = try Data(contentsOf: winebus, options: .alwaysMapped)
        for rpath in Payload.requiredWinebusRpaths {
            guard let needle = rpath.data(using: .utf8), busData.range(of: needle) != nil else {
                throw PatchError("winebus.so is missing the rpath \(rpath) — the controller would not appear. Rebuild the patcher with scripts/build-app.sh.")
            }
        }
    }

    private nonisolated static func fileSize(_ url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? nil
    }

    /// stdout and stderr are kept apart on purpose: `codesign -d --entitlements`
    /// prints "Executable=..." to stderr, and letting that land in front of the
    /// plist makes the next codesign reject the entitlement blob outright.
    @discardableResult
    private nonisolated static func run(_ tool: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args

        // stderr goes to a file rather than a second pipe so neither stream can
        // fill its buffer and stall the child while we drain the other one.
        let errFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("endfield-patcher-stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: errFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errFile) }

        let output = Pipe()
        process.standardOutput = output
        if let handle = try? FileHandle(forWritingTo: errFile) {
            process.standardError = handle
        }

        do {
            try process.run()
        } catch {
            throw PatchError("Could not run \((tool as NSString).lastPathComponent): \(error.localizedDescription)")
        }
        // Read to EOF before waiting so a full pipe can never stall the child.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let name = (tool as NSString).lastPathComponent
            let errText = (try? String(contentsOf: errFile, encoding: .utf8)) ?? ""
            let detail = (errText + text).trimmingCharacters(in: .whitespacesAndNewlines)
            throw PatchError("\(name) failed (exit \(process.terminationStatus))\(detail.isEmpty ? "" : ": \(detail)")")
        }
        return text
    }
}
