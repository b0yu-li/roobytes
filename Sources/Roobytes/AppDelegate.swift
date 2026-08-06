import AppKit
import UniformTypeIdentifiers

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    public static var shared: AppDelegate?

    private var windows: [DocumentWindowController] = []
    private var preferencesWindow: PreferencesWindowController?

    /// Vault root for a path: directories stay as-is; files use their parent folder.
    /// (Onboarding will let the user pick an explicit vault root — see BACKLOG.md.)
    static func resolvedVaultRoot(for url: URL) -> URL {
        let target = url.standardizedFileURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue {
            return target
        }
        return target.deletingLastPathComponent()
    }

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        applyAppearance()
        MemoryMonitor.shared.start()
        buildMenu()
        openLaunchWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Apply System / Light / Dark from settings to the whole app.
    func applyAppearance() {
        NSApp.appearance = RoobytesSettings.shared.appearance.nsAppearance
        NotificationCenter.default.post(name: .roobytesAppearanceDidChange, object: nil)
        for window in windows {
            window.refreshAppearance()
        }
        preferencesWindow?.window?.appearance = NSApp.appearance
    }

    /// Re-tint chrome + restyle editors after accent preset changes.
    func applyAccent() {
        MarkdownBridge.invalidateCheckboxImageCache()
        NotificationCenter.default.post(name: .roobytesAccentDidChange, object: nil)
        for window in windows {
            window.refreshAccent()
        }
    }

    /// Restore last note / vault when prefs allow; otherwise welcome (no hardcoded vault).
    private func openLaunchWindow() {
        let settings = RoobytesSettings.shared
        var folder: URL?
        var file: URL?

        if settings.reopenLastFileOnLaunch {
            if let lastFile = settings.lastFileURL {
                file = lastFile
                folder = Self.resolvedVaultRoot(for: lastFile)
            } else if let lastFolder = settings.lastFolderURL {
                folder = Self.resolvedVaultRoot(for: lastFolder)
            }
        }

        openNewWindow(folder: folder, file: file)

        if settings.tipsOnStartup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard RoobytesSettings.shared.tipsOnStartup else { return }
                self?.keyController()?.showRandomTip()
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard windows.contains(where: { $0.needsDiscardConfirmation }) else {
            return .terminateNow
        }
        // Sheets resolve asynchronously — walk the dirty windows one at a time and reply after.
        confirmNextDirtyWindowForTermination()
        return .terminateLater
    }

    /// Windows whose sheet already answered "Don't Save" — they stay dirty but must not re-ask.
    private var terminationApproved: Set<ObjectIdentifier> = []

    private func confirmNextDirtyWindowForTermination() {
        let pending = windows.first {
            $0.needsDiscardConfirmation && !terminationApproved.contains(ObjectIdentifier($0))
        }
        guard let pending else {
            terminationApproved.removeAll()
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        pending.showWindow(nil)
        pending.confirmDiscardWithSheet { [weak self] proceed in
            guard let self else { return }
            guard proceed else {
                self.terminationApproved.removeAll()
                NSApp.reply(toApplicationShouldTerminate: false)
                return
            }
            self.terminationApproved.insert(ObjectIdentifier(pending))
            self.confirmNextDirtyWindowForTermination()
        }
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openURL(url)
        }
    }

    public func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openURL(URL(fileURLWithPath: filename))
        return true
    }

    func removeWindow(_ controller: DocumentWindowController) {
        windows.removeAll { $0 === controller }
    }

    // MARK: - Windows

    @discardableResult
    func openNewWindow(folder: URL? = nil, file: URL? = nil) -> DocumentWindowController {
        // Skip welcome when opening a vault immediately — avoids Untitled save false positive.
        let controller = DocumentWindowController(seedWelcome: folder == nil && file == nil)
        windows.append(controller)
        if let folder {
            controller.openFolder(folder, preferredFile: file)
        } else if let file {
            controller.openFile(file)
        }
        if RoobytesSettings.shared.restorePinOnLaunch {
            controller.setPinned(RoobytesSettings.shared.isPinned)
        }
        controller.showWindowBalanced()
        return controller
    }

    private func keyController() -> DocumentWindowController? {
        if let key = NSApp.keyWindow,
           let match = windows.first(where: { $0.window === key })
        {
            return match
        }
        return windows.last
    }

    /// Vault root of the key (or last) document window, if any.
    func keyVaultURL() -> URL? {
        keyController()?.folderURL
    }

    private func openURL(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            let folder = Self.resolvedVaultRoot(for: url)
            if let key = keyController(), key.folderURL == nil, !key.needsDiscardConfirmation {
                key.openFolder(folder)
                key.showWindow(nil)
            } else {
                openNewWindow(folder: folder)
            }
        } else if MarkdownDocument.isMarkdownFile(url) {
            let folder = Self.resolvedVaultRoot(for: url)
            if let key = keyController(),
               key.folderURL == nil || key.folderURL?.standardizedFileURL == folder
            {
                key.openFile(url)
                key.showWindow(nil)
            } else {
                openNewWindow(folder: folder, file: url)
            }
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(appAction("About Roobytes", #selector(showAbout(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(appAction("Settings…", #selector(showPreferences(_:)), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Roobytes",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Roobytes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(appAction("New", #selector(newDocument(_:)), key: "n"))
        fileMenu.addItem(appAction("New Window", #selector(newWindow(_:)), key: "n", modifiers: [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(appAction("Open…", #selector(openDocument(_:)), key: "o"))
        fileMenu.addItem(appAction("Open Folder…", #selector(openFolder(_:)), key: "o", modifiers: [.command, .shift]))
        fileMenu.addItem(appAction("Go to File…", #selector(goToFile(_:)), key: "p"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(appAction("Save", #selector(saveDocument(_:)), key: "s"))
        fileMenu.addItem(appAction("Save As…", #selector(saveDocumentAs(_:)), key: "S"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(appAction("Find…", #selector(findInNote(_:)), key: "f"))

        let formatItem = NSMenuItem()
        mainMenu.addItem(formatItem)
        let formatMenu = NSMenu(title: "Format")
        formatItem.submenu = formatMenu
        formatMenu.addItem(appAction("Bold", #selector(toggleBold(_:)), key: "b"))
        formatMenu.addItem(appAction("Italic", #selector(toggleItalic(_:)), key: "i"))
        formatMenu.addItem(.separator())
        formatMenu.addItem(appAction("Heading 1", #selector(applyHeading1(_:)), key: "1", modifiers: [.command, .option]))
        formatMenu.addItem(appAction("Heading 2", #selector(applyHeading2(_:)), key: "2", modifiers: [.command, .option]))
        formatMenu.addItem(appAction("Heading 3", #selector(applyHeading3(_:)), key: "3", modifiers: [.command, .option]))
        formatMenu.addItem(appAction("Body", #selector(applyBody(_:)), key: "0", modifiers: [.command, .option]))
        formatMenu.addItem(.separator())
        formatMenu.addItem(appAction("Bulleted List", #selector(applyBulletList(_:)), key: "8", modifiers: [.command, .shift]))
        formatMenu.addItem(.separator())
        formatMenu.addItem(appAction("Toggle Task", #selector(toggleTask(_:)), key: "\r"))
        // Vim-only chords (`md` / `mD` / `mf`); multi-char keyEquivalent is unsupported.
        formatMenu.addItem(appAction("Mark Task Done (md)", #selector(markTaskDone(_:)), key: ""))
        formatMenu.addItem(appAction("Mark Task Open (mD)", #selector(markTaskOpen(_:)), key: ""))
        formatMenu.addItem(appAction("Focus Task (mf)", #selector(toggleFocusTask(_:)), key: ""))
        // Vim-only chords (`gx` / `gX`); shown in the title — multi-char keyEquivalent is unsupported.
        formatMenu.addItem(appAction("Open Link (gx)", #selector(openLinkInFirefox(_:)), key: ""))
        formatMenu.addItem(appAction("Open Link in Firefox Private (gX)", #selector(openLinkInFirefoxPrivate(_:)), key: ""))

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(appAction("Float on Top", #selector(togglePinWindow(_:)), key: "p", modifiers: [.command, .shift]))
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// Menu items that live on AppDelegate need an explicit target — nil target + text-first-responder greys them out.
    private func appAction(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    // MARK: - Actions

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.7"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "17"
        let credits = NSAttributedString(
            string: "Native markdown notes · WYSIWYG · PT Mono · live Mem\nVersion \(version)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Roobytes",
            .applicationVersion: version,
            .version: build,
            .credits: credits,
        ])
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
        }
        preferencesWindow?.showPreferences()
    }

    @objc private func newDocument(_ sender: Any?) {
        if let key = keyController() {
            key.newUntitled()
        } else {
            openNewWindow().newUntitled()
        }
    }

    @objc private func newWindow(_ sender: Any?) {
        openNewWindow()
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.markdownContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openURL(url)
    }

    @objc private func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openURL(url)
    }

    @objc private func goToFile(_ sender: Any?) {
        guard let key = keyController() else { return }
        if key.isFileSwitcherVisible {
            key.dismissFileSwitcher()
        } else {
            key.showFileSwitcher()
        }
    }

    @objc private func saveDocument(_ sender: Any?) {
        keyController()?.save()
    }

    @objc private func saveDocumentAs(_ sender: Any?) {
        keyController()?.saveAs()
    }

    @objc private func findInNote(_ sender: Any?) {
        keyController()?.showFind()
    }

        @objc private func togglePinWindow(_ sender: Any?) {
        keyController()?.togglePin(sender)
    }

    @objc private func toggleBold(_ sender: Any?) {
        keyController()?.toggleBold()
    }

    @objc private func toggleItalic(_ sender: Any?) {
        keyController()?.toggleItalic()
    }

    @objc private func applyHeading1(_ sender: Any?) {
        keyController()?.applyHeading(1)
    }

    @objc private func applyHeading2(_ sender: Any?) {
        keyController()?.applyHeading(2)
    }

    @objc private func applyHeading3(_ sender: Any?) {
        keyController()?.applyHeading(3)
    }

    @objc private func applyBody(_ sender: Any?) {
        keyController()?.applyBody()
    }

    @objc private func applyBulletList(_ sender: Any?) {
        keyController()?.applyBulletList()
    }

    @objc private func toggleTask(_ sender: Any?) {
        keyController()?.toggleTask()
    }

    @objc private func markTaskDone(_ sender: Any?) {
        keyController()?.markTaskDone()
    }

    @objc private func markTaskOpen(_ sender: Any?) {
        keyController()?.markTaskOpen()
    }

    @objc private func toggleFocusTask(_ sender: Any?) {
        keyController()?.toggleFocusTask()
    }

    @objc private func openLinkInFirefox(_ sender: Any?) {
        keyController()?.openURLUnderCaret(privateBrowsing: false)
    }

    @objc private func openLinkInFirefoxPrivate(_ sender: Any?) {
        keyController()?.openURLUnderCaret(privateBrowsing: true)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTask(_:)) {
            return keyController()?.canToggleTask == true
        }
        if menuItem.action == #selector(markTaskDone(_:)) {
            return keyController()?.canMarkTaskDone == true
        }
        if menuItem.action == #selector(markTaskOpen(_:)) {
            return keyController()?.canMarkTaskOpen == true
        }
        if menuItem.action == #selector(toggleFocusTask(_:)) {
            return keyController()?.canToggleFocusTask == true
        }
        if menuItem.action == #selector(goToFile(_:)) {
            return keyController()?.folderURL != nil
        }
        if menuItem.action == #selector(togglePinWindow(_:)) {
            menuItem.state = keyController()?.isPinned == true ? .on : .off
            return keyController() != nil
        }
        return true
    }
}
