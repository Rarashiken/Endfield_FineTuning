import AppKit

struct LicenseLink: Hashable {
    let label: String
    let url: String
}

struct LicenseComponent: Identifiable, Hashable {
    let id: String
    let name: String
    let license: String
    let summary: String
    let notice: String?
    let textFile: String
    let links: [LicenseLink]

    static let all: [LicenseComponent] = [
        LicenseComponent(
            id: "finetuning-patcher",
            name: "FineTuning Patcher",
            license: "MIT",
            summary: "This application — the interface and patching logic.",
            notice: "Copyright © 2026 Endfield_FineTuning contributors.",
            textFile: "mit-finetuning-patcher.txt",
            links: [
                LicenseLink(label: "Project repository", url: "https://github.com/Rarashiken/Endfield_FineTuning"),
            ]
        ),
        LicenseComponent(
            id: "finewine-upstream",
            name: "Endfield_FineWine (upstream)",
            license: "MIT",
            summary: "The project this one continues. It found the two Rosetta 2 bugs and ported the dw-proton anti-cheat patches; all 23 of those patches are a prerequisite for the modules bundled here.",
            notice: "Copyright © 2026 Endfield_FineWine contributors.",
            textFile: "mit-finewine-patcher-upstream.txt",
            links: [
                LicenseLink(label: "Upstream repository", url: "https://github.com/stoicswe/Endfield_FineWine"),
            ]
        ),
        LicenseComponent(
            id: "crossover-wine-modules",
            name: "CrossOver Wine — patched modules",
            license: "LGPL-2.1-or-later",
            summary: "The pre-built Wine modules bundled inside this app and installed into your CrossOver copy: ntdll.so, winebus.so, winebus.sys, ntoskrnl.exe and kernel32.dll. They are built from CodeWeavers' freely published CrossOver 26.3 Wine source with this project's patches applied.",
            notice: "Wine — Copyright © the Wine project authors. CrossOver Wine modifications — Copyright © CodeWeavers, Inc. Endfield patches — Copyright © Endfield_FineWine contributors and the dw-proton authors. The complete corresponding source is available at the links below.",
            textFile: "lgpl-2.1.txt",
            links: [
                LicenseLink(label: "Complete corresponding source (patches + build scripts)", url: "https://github.com/Rarashiken/Endfield_FineTuning"),
                LicenseLink(label: "CodeWeavers FOSS source for CrossOver", url: "https://www.codeweavers.com/crossover/source"),
                LicenseLink(label: "CrossOver source archive", url: "https://media.codeweavers.com/pub/crossover/source/"),
                LicenseLink(label: "Wine project", url: "https://www.winehq.org/"),
            ]
        ),
        LicenseComponent(
            id: "dwproton-patches",
            name: "dw-proton patches",
            license: "LGPL-2.1-or-later",
            summary: "The anti-cheat compatibility patches ported from the Linux dw-proton (Dawn Winery) project. They are part of the bundled Wine modules above.",
            notice: "Authors: Etaash Mathamsetty, Ziia Shi (mkrsym1), NelloKudo, and other dw-proton contributors.",
            textFile: "lgpl-2.1.txt",
            links: [
                LicenseLink(label: "dw-proton / Dawn Winery", url: "https://dawn.wine/"),
            ]
        ),
    ]
}

// MARK: - AppKit licences window

final class LicensesWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private static var shared: LicensesWindow?
    private let table = NSTableView()
    private let text = NSTextView()

    static func show() {
        if shared == nil { shared = LicensesWindow() }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Licenses"
        window.center()
        self.init(window: window)
        build()
        if !LicenseComponent.all.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            showComponent(0)
        }
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let column = NSTableColumn(identifier: .init("name"))
        column.width = 220
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 38
        let left = NSScrollView()
        left.documentView = table
        left.hasVerticalScroller = true
        left.borderType = .bezelBorder

        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textContainerInset = NSSize(width: 8, height: 8)
        let right = NSScrollView()
        right.documentView = text
        right.hasVerticalScroller = true
        right.borderType = .bezelBorder

        let split = NSStackView(views: [left, right])
        split.orientation = .horizontal
        split.spacing = 10
        split.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: 230),
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { LicenseComponent.all.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = LicenseComponent.all[row]
        let name = NSTextField(labelWithString: c.name)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        let lic = NSTextField(labelWithString: c.license)
        lic.font = .systemFont(ofSize: 10)
        lic.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [name, lic])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if row >= 0 { showComponent(row) }
    }

    private func showComponent(_ row: Int) {
        let c = LicenseComponent.all[row]
        var body = "\(c.name)  —  \(c.license)\n\n\(c.summary)\n"
        if let notice = c.notice { body += "\n\(notice)\n" }
        for link in c.links { body += "\n\(link.label): \(link.url)" }
        body += "\n\n" + String(repeating: "─", count: 72) + "\n\n"
        if let url = Bundle.main.url(forResource: c.textFile, withExtension: nil, subdirectory: "licenses"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            body += contents
        } else {
            body += "(license text not bundled: \(c.textFile))"
        }
        text.string = body
        text.scrollToBeginningOfDocument(nil)
    }
}
