# Roobytes

Native macOS markdown notes — Live Preview, Vim-inspired Normal mode, PT Mono, live Mem (physical footprint).

## Run

```bash
./run.sh
```

```bash
./test.sh   # RoobytesCore caret / fold / list-marker mapping
```

`./run.sh` always runs `./package-app.sh` first (release build → `/Applications/Roobytes.app`), then launches Roobytes. Do not claim a version is shipped until that install is updated.

Opens the last edited note when possible (see **Settings…** / `⌘,`); otherwise a welcome window. Choose a vault with **Open Folder…** (`⇧⌘O`).

## Features

- Spotlight / Raycast: **Roobytes** (installed to `/Applications`)
- Settings: **Roobytes → Settings…** (`⌘,`) — appearance, accent, reopen last file, restore pin, tips on startup, word completion, spell checking, sound effects, debug logging
- Go to File: **`⌘P`** — frecency-ranked vault jump (fuzzy filter)
- Daily notes: **`:daily` / `:today`** — opens or creates `diaries/YYYY-MM-DD.md` from vault-root `daily-notes-temp.md` (template must exist)
- Vim: **`Esc`** Normal · **`u`** undo · **`⌃d`/`⌃u`** half-page scroll · **`r`** · **`za`/`zc`/`zo`** fold nested lists · **`md`/`mD`** mark done/open · **`mf`** focus · **`'f`** go to focus · **`]t`/`[t`** next/prev undone task · **`gx`/`gX`** open URL (default browser / Firefox Private) · **`:w` / `:e!` / `:q` / `:pin` / `:folddone` / `:complete` / `:h` / `:tips`** · **`Tab`** complete (Insert words / `:` cmds) · **`5j`** · **`dd`** · **`yy`** · **`⌘↩`** cycle task

## Ship

```bash
./ship.sh patch|minor|major -m "changelog bullet"
```

## License

[MIT](LICENSE)
