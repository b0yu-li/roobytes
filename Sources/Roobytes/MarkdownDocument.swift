import Foundation
import UniformTypeIdentifiers

@MainActor
final class MarkdownDocument {
    private(set) var url: URL?
    private(set) var isDirty = false
    /// True only after the user typed/edited — not after WYSIWYG round-trip sync.
    private(set) var hasUserEdits = false

    private var textStorage: String = ""

    var text: String {
        get { textStorage }
        set { updateText(newValue, userEdit: true) }
    }

    var displayName: String {
        if let url {
            return url.lastPathComponent
        }
        if textStorage == Self.welcomeMarkdown {
            return "Welcome"
        }
        return "Untitled.md"
    }

    var folderURL: URL? {
        url?.deletingLastPathComponent()
    }

    init(url: URL? = nil, text: String = "", isDirty: Bool = false, hasUserEdits: Bool = false) {
        self.url = url
        self.textStorage = text
        self.isDirty = isDirty
        self.hasUserEdits = hasUserEdits
    }

    static func welcome() -> MarkdownDocument {
        MarkdownDocument(text: welcomeMarkdown, isDirty: false, hasUserEdits: false)
    }

    /// Empty pristine buffer used when a vault folder will be opened immediately.
    static func empty() -> MarkdownDocument {
        MarkdownDocument(text: "", isDirty: false, hasUserEdits: false)
    }

    static func untitled(in folder: URL? = nil) -> MarkdownDocument {
        _ = folder
        return MarkdownDocument(text: "# Untitled\n\n", isDirty: true, hasUserEdits: true)
    }

    func load(from fileURL: URL) throws {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        url = fileURL
        replaceTextWithoutMarkingDirty(contents)
    }

    /// Apply editor text. `userEdit: true` marks dirty; false only updates storage (round-trip sync).
    func updateText(_ newText: String, userEdit: Bool) {
        guard newText != textStorage else { return }
        textStorage = newText
        if userEdit {
            isDirty = true
            hasUserEdits = true
        }
    }

    /// Sync editor ↔ model after load/restyle without treating it as a user edit.
    func replaceTextWithoutMarkingDirty(_ newText: String) {
        textStorage = newText
        isDirty = false
        hasUserEdits = false
    }

    func markClean() {
        isDirty = false
        hasUserEdits = false
    }

    func markUserEdited() {
        isDirty = true
        hasUserEdits = true
    }

    func save() throws {
        guard let url else {
            throw DocumentError.noFileURL
        }
        try write(to: url)
    }

    func save(to fileURL: URL) throws {
        try write(to: fileURL)
        url = fileURL
    }

    private func write(to fileURL: URL) throws {
        try textStorage.write(to: fileURL, atomically: true, encoding: .utf8)
        isDirty = false
        hasUserEdits = false
    }

    enum DocumentError: LocalizedError {
        case noFileURL

        var errorDescription: String? {
            switch self {
            case .noFileURL:
                return "This note has not been saved yet."
            }
        }
    }

    static let markdownContentTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") {
            types.append(md)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            types.append(markdown)
        }
        return types
    }()

    static func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "txt"].contains(ext)
    }

    private static let welcomeMarkdown = """
    # Roobytes

    Edit **what you see** — headings, emphasis, and lists render as you write. Still one native process.

    ## Get started

    1. **File → Open Folder…** (`⇧⌘O`) to open a vault
    2. **`⌘P`** jumps to a note (frecency + fuzzy)
    3. **Mem** lives in the title bar (left of the pin) — physical footprint, same as Activity Monitor

    ## Tips

    - `⌘P` Go to File · `Esc` closes switcher (or Insert → Normal preview)
    - Vim: Normal = preview · `gg`/`G` · `md`/`mD` done/open · `mf` focus · `'f` jump · `:w` save · `:e!` discard · `:folddone` fold done nests · `hjkl`/`wb`/`e`/`zz`/`za` fold · `o`/`O` · `⌃e`/`⌃y` · `i`/`a`/`I`/`A` Insert · `⌘↩` cycle task
    - `⌘B` bold · `⌘I` italic · `⌥⌘1`–`3` headings
    - Spotlight: `⌘Space` → type **Roobytes**

    ```swift
    print("hello from Roobytes")
    ```

    > Activity Monitor: search for **Roobytes** — one process, no GPU helper.
    """
}
