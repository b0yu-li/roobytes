# Roobytes backlog

Parked features — not in the current release.

## Onboarding: vault + daily template

**Status:** partial — daily template + diaries folder picker shipped; vault first-run wizard still parked

**Intent:** First launch (and any session with no vault) should guide the user instead of assuming a personal folder.

1. **Choose vault folder** — picker / welcome CTA to set the notes root (persisted; used by Go to File, reopen, `:daily`). Still: Open Folder… (`⇧⌘O`).
2. **Daily notes template** — **done for fixed vault-root `daily-notes-temp.md`:** `:daily` / `:today` prompts Create starter / Choose file… when missing; Settings → Daily notes has the same actions.
3. **Diaries folder** — **done:** Settings → Daily notes Choose folder… / Create folder / Use diaries; `:daily` auto-creates the configured folder when missing (default `diaries/`).
4. Clear errors when vault or template is missing (status flashes + setup alert).

**Still needed for polished first-run:** dedicated vault onboarding when no folder is open.

## Click checkbox to toggle task

**Status:** keyboard command shipped (⌘↩); click-to-toggle still parked

**Intent:** Click the collapsed checkbox attachment to flip `[ ]` ↔ `[x]` without entering the raw slug.

**Available now:** **Format → Toggle Task** (`⌘↩`) toggles the caret line.

**Why click is parked:** Click-to-toggle on task lines did not feel reliable (hit testing / Live Preview active-line interaction).

**Prior art (removed for click):**

- `RoobytesEditorTextView` mouseDown → `handleCheckboxClick`
- `EditorViewController.toggleTaskCheckbox(atCharacter:)`

**When revisiting click:** Hit-test only the attachment glyph (not the whole task line), keep the line collapsed after toggle, and avoid fighting `activeSourceLine` / restyle.
