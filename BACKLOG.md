# Roobytes backlog

Parked features — not in the current release.

## Onboarding: vault + daily template

**Status:** not started — required before a polished first-run for open source

**Intent:** First launch (and any session with no vault) should guide the user instead of assuming a personal folder.

1. **Choose vault folder** — picker / welcome CTA to set the notes root (persisted; used by Go to File, reopen, `:daily`).
2. **Daily notes template** — when the user enables or first runs `:daily` / `:today`, require setup of the vault-root template (`daily-notes-temp.md` today, or a user-chosen path): create from a starter, pick an existing file, or skip daily notes until configured.
3. Clear errors when vault or template is missing (partially done in status messages).

**Until then:** Open Folder… (`⇧⌘O`) to select a vault; place `daily-notes-temp.md` at the vault root before using `:daily`.

## Click checkbox to toggle task

**Status:** keyboard command shipped (⌘↩); click-to-toggle still parked

**Intent:** Click the collapsed checkbox attachment to flip `[ ]` ↔ `[x]` without entering the raw slug.

**Available now:** **Format → Toggle Task** (`⌘↩`) toggles the caret line.

**Why click is parked:** Click-to-toggle on task lines did not feel reliable (hit testing / Live Preview active-line interaction).

**Prior art (removed for click):**

- `RoobytesEditorTextView` mouseDown → `handleCheckboxClick`
- `EditorViewController.toggleTaskCheckbox(atCharacter:)`

**When revisiting click:** Hit-test only the attachment glyph (not the whole task line), keep the line collapsed after toggle, and avoid fighting `activeSourceLine` / restyle.
