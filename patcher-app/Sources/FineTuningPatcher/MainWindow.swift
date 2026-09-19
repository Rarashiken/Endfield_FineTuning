import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let c = MainWindowController()
        controller = c
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let name = ProcessInfo.processInfo.processName
        appMenu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = main
    }
}

final class MainWindowController: NSWindowController {
    private let engine = PatcherEngine()
    private var source: URL?

    private let sourceLabel = NSTextField(labelWithString: "No CrossOver selected")
    private let detailLabel = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "Choose CrossOver…", target: nil, action: nil)
    private let patchButton = NSButton(title: "Patch", target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal in Finder", target: nil, action: nil)
    private let licensesButton = NSButton(title: "Licenses", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private var logView = NSTextView()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "FineTuning Patcher"
        window.center()
        self.init(window: window)
        build()
        engine.onChange = { [weak self] in self?.render() }
        autodetect()
        render()
    }

    // MARK: - layout

    private func build() {
        guard let content = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "Patch CrossOver 26.3 for Arknights: Endfield")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let blurb = NSTextField(wrappingLabelWithString:
            "Makes a copy of CrossOver and swaps in five patched Wine modules. "
          + "Your original CrossOver is never modified. A DualSense reports itself "
          + "as a DualSense, so games show PlayStation button glyphs.")
        blurb.font = .systemFont(ofSize: 11)
        blurb.textColor = .secondaryLabelColor

        sourceLabel.font = .systemFont(ofSize: 12, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor

        chooseButton.target = self; chooseButton.action = #selector(choose)
        patchButton.target  = self; patchButton.action  = #selector(patch)
        patchButton.keyEquivalent = "\r"
        revealButton.target = self; revealButton.action = #selector(reveal)
        licensesButton.target = self; licensesButton.action = #selector(showLicenses)
        licensesButton.bezelStyle = .inline

        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1   // replaced with the real step count once patching starts
        progress.controlSize = .small

        // NSTextView.scrollableTextView() wires up the text container, resizing
        // masks and clip view. Doing it by hand and forgetting one of them gives a
        // text view that accepts strings and renders nothing.
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return }
        logView = tv
        logView.isEditable = false
        logView.isSelectable = true
        logView.drawsBackground = true
        logView.backgroundColor = .textBackgroundColor
        logView.textColor = .textColor
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 6, height: 6)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let buttons = NSStackView(views: [chooseButton, patchButton, revealButton, NSView(), licensesButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [heading, blurb, sourceLabel, detailLabel, buttons, progress, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            blurb.widthAnchor.constraint(equalToConstant: 580),
            buttons.widthAnchor.constraint(equalToConstant: 580),
            progress.widthAnchor.constraint(equalToConstant: 580),
            scroll.widthAnchor.constraint(equalToConstant: 580),
            scroll.heightAnchor.constraint(equalToConstant: 210),
        ])
    }

    // MARK: - actions

    private func autodetect() {
        let candidate = URL(fileURLWithPath: "/Applications/CrossOver.app")
        if FileManager.default.fileExists(atPath: candidate.path) { select(candidate) }
    }

    @objc private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose your CrossOver application"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { select(url) }
    }

    private func select(_ url: URL) {
        source = url
        let info = CrossOverInfo(url: url)
        sourceLabel.stringValue = info.displayName + "  —  version " + (info.version ?? "unknown")
        if !info.hasWineModules {
            detailLabel.stringValue = "This does not look like a CrossOver installation (Wine modules not found)."
            detailLabel.textColor = .systemRed
        } else if !info.isExpectedVersion {
            detailLabel.stringValue = "Warning: these modules were built for CrossOver \(CrossOverInfo.expectedVersion). Patching a different version is untested and likely to break."
            detailLabel.textColor = .systemOrange
        } else {
            detailLabel.stringValue = "Ready. The patched copy will be created next to your Applications folder."
            detailLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func patch() {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.title = "Where should the patched copy go?"
        panel.nameFieldStringValue = Self.suggestedDestinationName()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        log("Patching \(source.path)\n     ->  \(destination.path)\n")
        engine.patch(source: source, destination: destination)
    }

    /// The patch replaces whatever is at the destination, and the obvious default
    /// name is exactly the app someone may already be launching the game with.
    /// Step aside instead of proposing to overwrite it.
    private static func suggestedDestinationName() -> String {
        let base = "CrossOver-Endfield"
        let fm = FileManager.default
        var candidate = "\(base).app"
        var n = 2
        while fm.fileExists(atPath: "/Applications/\(candidate)") {
            candidate = "\(base)-\(n).app"
            n += 1
        }
        return candidate
    }

    @objc private func reveal() {
        guard let url = engine.patchedApp else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func showLicenses() { LicensesWindow.show() }

    // MARK: - rendering

    private var renderedSteps = 0

    private func render() {
        let steps = engine.steps
        chooseButton.isEnabled = !engine.isRunning
        patchButton.isEnabled = !engine.isRunning && source != nil
        revealButton.isEnabled = engine.patchedApp != nil
        if !steps.isEmpty { progress.maxValue = Double(steps.count) }
        progress.doubleValue = Double(steps.filter { $0.status == .done }.count)

        while renderedSteps < steps.count {
            let s = steps[renderedSteps]
            if s.status == .running { log("  • \(s.label)…"); renderedSteps += 1 } else { break }
        }
        if let done = steps.last(where: { $0.status == .done }), done.id == steps.count - 1,
           let app = engine.patchedApp {
            log("\nDone. Patched copy: \(app.path)")
            renderedSteps = Int.max
        }
        if let error = engine.errorMessage {
            log("\nFAILED: \(error)")
            engine.errorMessage = nil
        }
    }

    private func log(_ line: String) {
        logView.string += line + "\n"
        logView.scrollToEndOfDocument(nil)
    }
}
