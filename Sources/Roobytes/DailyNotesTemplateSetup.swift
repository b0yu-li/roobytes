import AppKit
import UniformTypeIdentifiers

/// In-app setup for vault-root `daily-notes-temp.md` (Create starter / Choose file).
@MainActor
enum DailyNotesTemplateSetup {
    /// Present missing-template alert. Returns `true` when a template was installed.
    @discardableResult
    static func presentMissingTemplateAlert(
        vault: URL,
        window: NSWindow?
    ) -> Bool {
        _ = window
        let alert = NSAlert()
        alert.messageText = "Daily notes template needed"
        alert.informativeText =
            "`:daily` creates today’s note from \(DailyNotes.templateFileName) at the vault root. Create a starter, or choose an existing markdown file to copy there."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create starter")
        alert.addButton(withTitle: "Choose file…")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return installStarter(vault: vault, confirmReplace: false)
        case .alertSecondButtonReturn:
            return chooseAndInstall(vault: vault, confirmReplace: false)
        default:
            return false
        }
    }

    /// Settings: write starter (confirms replace when template already exists).
    @discardableResult
    static func createStarterFromSettings(vault: URL) -> Bool {
        installStarter(vault: vault, confirmReplace: true)
    }

    /// Settings: pick a file and copy into the template path.
    @discardableResult
    static func chooseFileFromSettings(vault: URL) -> Bool {
        chooseAndInstall(vault: vault, confirmReplace: true)
    }

    // MARK: - Private

    private static func installStarter(vault: URL, confirmReplace: Bool) -> Bool {
        if confirmReplace,
           DailyNotes.templateExists(vault: vault),
           !confirmOverwrite()
        {
            return false
        }
        do {
            try DailyNotes.installStarterTemplate(vault: vault)
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    private static func chooseAndInstall(vault: URL, confirmReplace: Bool) -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.markdownContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = vault
        panel.message = "Choose a markdown file to copy as \(DailyNotes.templateFileName)"
        panel.prompt = "Use as Template"
        guard panel.runModal() == .OK, let source = panel.url else { return false }

        if confirmReplace,
           DailyNotes.templateExists(vault: vault),
           !confirmOverwrite()
        {
            return false
        }
        do {
            try DailyNotes.installTemplate(copying: source, vault: vault)
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    private static func confirmOverwrite() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace daily template?"
        alert.informativeText =
            "\(DailyNotes.templateFileName) already exists in this vault. Replace it?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not install template"
        if case DailyNotes.EnsureError.writeFailed(let detail) = error {
            alert.informativeText = detail
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
