# OkayWrite — trimmed notepad-only app (design)

**Date:** 2026-09-12
**Status:** Draft for review
**Repo:** okaykoa/OkayWrite
**Branch:** `notepad-trim` (off `main`)

## Context & goal

OkayWrite today is a thin **overlay** on stock KOReader: it ships KOReader's prebuilt Kindle
binary unchanged and reskins it via Lua userpatches (`koreader/patches/`). That gets a
writing-focused experience with almost no engineering cost, but the underlying app is still
"all of KOReader," just steered away from — the reader engine, ~60 languages, and every
plugin still ship and still exist, just hidden behind settings.

This branch does the "strip later" half of OkayWrite's roadmap: make the shipped app
**actually** just a notepad, not a big app in a costume. Scope, confirmed during design:

- **Kindle only.** No other device/platform.
- **Notepad + file manager + on-screen keyboard + Bluetooth keyboard.** Same four surfaces
  OkayWrite already has, kept.
- **Localization limited to EFIGS** (English, French, Italian, German, Spanish) — and this
  means actually removing the other ~55 languages' data from the build, not just hiding the
  picker.
- **Physical-keyboard layouts for all five EFIGS languages**, extending the existing
  from-scratch layout resolver (today: US only).
- **Terminal-style word/line cursor movement** via a Bluetooth keyboard's modifiers: Alt +
  Left/Right jumps by word, Cmd/Meta + Left/Right jumps to line start/end. No physical d-pad
  hardware involved — this is BT-keyboard-modifier + arrow-key only.

## Strategy: prune the release, don't recompile

Two approaches were considered:

- **(Chosen) Prune the downloaded release tree.** KOReader's Kindle release already splits a
  compiled core (`koreader` binary, `libs/`, `data/` — MuPDF, CRengine, LuaJIT, fonts) from a
  plain-file application layer (`frontend/` Lua, `plugins/*.koreader` Lua, `l10n/` translation
  folders, `frontend/ui/data/keyboardlayouts/*.lua`). `build.sh` already unzips this release
  before layering patches. This branch adds a **prune step** in that same place: delete the
  reader-only frontend apps, non-notepad plugins, and every `l10n/`/keyboard-layout folder
  outside EFIGS. No cross-compilation, no fork of the C core, no new toolchain — the existing
  copy-a-patch-and-relaunch dev loop is unaffected.
- **(Rejected for now) Full source fork + Kindle cross-compile.** The only way to also shrink
  the compiled binary itself, but requires standing up KOReader's ARM cross-compilation
  toolchain and submodules, and taking on a real source fork's merge burden on every upstream
  KOReader update. Rejected as disproportionate to "a very small writing app"; revisit only if
  the compiled binary's size/footprint becomes an actual problem.

**Consequence:** the compiled `koreader` binary (MuPDF/CRengine/etc.) still ships as one
non-shrinkable blob. What gets smaller and genuinely simpler is the *application* the user
can actually reach: no dead reader/plugin menus, no dead code paths, no 55 extra languages on
disk.

## Repository layout (additions)

```
overlay/koreader/prune/                 new: prune manifests, read by build.sh
  plugins-delete.txt                    plugin directory names to remove
  l10n-keep.txt                         language codes to keep (en, es, fr, it, de)
overlay/koreader/patches/                unchanged — existing New file / Save as / keyboard patches
overlay/koreader/patches/okaywrite/keyboard_layout.lua   extended with fr/it/de/es layouts
build.sh                                 gains a prune step between unzip and overlay-copy
```

## Components

### 1. Prune step (new)

After `build.sh` unzips the pinned KOReader Kindle release and before the overlay patches are
copied in, delete:

- **Reader-only frontend code** — the PDF/EPUB/DjVu-related UI under `frontend/apps/reader/`
  and any reader-only frontend modules that are not reachable once `start_with = filemanager`
  and `.txt`/`.md` always route to the text editor (per the existing `2-okaywrite.lua`
  settings). File manager, text editor, and core UI/input/settings machinery are kept.
- **Non-notepad plugins** — dictionary, OPDS, Calibre companion, cloud storage/sync
  (Dropbox/WebDAV/FTP), statistics, KOReader's own `terminal.koreader` (an SSH/terminal
  emulator plugin — unrelated to this app's word/line cursor movement, just a name
  collision), and similarly unrelated plugins. Kept: `texteditor.koplugin`,
  `externalkeyboard.koplugin`, and any plugin the kept surfaces actually depend on.
- **Non-EFIGS localization** — every `l10n/` language folder except `en`, `es`, `fr`, `it`,
  `de`, and the matching entries in `frontend/ui/data/keyboardlayouts/` (KOReader's per-language
  on-screen virtual keyboards), so the on-screen keyboard's language list matches the UI
  language list.

The exact keep/delete list is enumerated against the pinned `KO_VERSION` source tree during
implementation, verified empirically (see Testing) rather than assumed from folder names alone,
since some plugins may be depended on by kept surfaces in non-obvious ways.

### 2. Existing behavior patches — unchanged

New file (`2-okaywrite-newfile.lua`), Save as (`2-okaywrite-saveas.lua`), and the
physical-keyboard resolver/wrapper (`2-okaywrite-keyboard.lua` +
`okaywrite/keyboard_layout.lua`) are not reworked. They already do what this app needs.

### 3. Keyboard layout data — extended, not redesigned

`okaywrite/keyboard_layout.lua`'s `M.layouts` table gains `fr`, `it`, `de`, `es` entries
alongside the existing `us` one, using the same shape already defined (`{base, shift, altgr,
shift_altgr}` per non-letter key, plus AltGr letter overrides for accented characters). This
covers AZERTY (fr), QWERTZ (de), and the accented-punctuation differences in the it/es
QWERTY-family layouts. `M.resolve` and the `InputText:onKeyPress` wrapper need no structural
change — they already dispatch on `layout_name`.

### 4. Terminal-style word/line cursor movement (new)

Extends the existing `InputText:onKeyPress` wrapper (same wrapper that handles the printable
case today) with two new non-printable cases, both delegating to the original for everything
else as it does now:

- **Alt + Left/Right** → move cursor by word (left/right).
- **Cmd/Meta + Left/Right** → move cursor to line start/end.

This requires tracking a third modifier (Meta/Super) alongside the existing Shift/AltGr
tracking, and — following the same pattern used to fix `;`/`-`/`=`/`[`/`]`/backtick naming for
the printable case — normalizing the event-map name for the Meta/Super key on
`PhysicalKeyboardConnected`, since a stock event map may not name it usably. Word/line jump
itself is implemented against whatever cursor-movement primitives the text-input widget already
exposes for Home/End/arrow movement (confirmed during implementation).

## Non-goals / explicit scope lines

- No cross-compilation or shrinking of the compiled `koreader` binary (Approach B, deferred
  indefinitely unless binary footprint becomes an actual problem).
- No wireless/cloud export. Those plugins are *deleted* by the prune step, not merely hidden —
  USB copy of plain `.txt`/`.md` under `/mnt/us/OkayWrite` remains the only export path. This
  narrows OkayWrite's existing roadmap item (wireless/cloud sync was previously a "spike");
  for this app it's dropped rather than deferred.
- No physical d-pad hardware support. "Command and Alt dpad movement" means a Bluetooth
  keyboard's own modifier + arrow keys, not the Kindle's on-device 5-way button.
- No dead keys/compose sequences, no non-Latin scripts (carried over from the existing keyboard
  design's scope line — applies to the new fr/it/de/es layouts too).
- No new Bluetooth pairing UI/helper; still assumes `kindle-hid-passthrough` is user-installed,
  same as the existing keyboard feature.

## Docs & build changes

- **README:** describe the trimmed app (notepad + file manager + on-screen/BT keyboard, EFIGS
  only) as what OkayWrite *is* on this branch, not a roadmap item; note that reader/PDF/EPUB
  support and non-EFIGS languages are removed, not hidden.
- **INSTALL.md:** unchanged sections still apply (BT pairing via `kindle-hid-passthrough`
  outside the app).
- **build.sh:** add the prune step (reads `overlay/koreader/prune/*` manifests) between unzip
  and overlay-copy; keep `KO_VERSION` pin as-is unless prune verification requires a bump.

## Verification

**Prune-list validation (empirical, before encoding into build.sh):** delete candidate
plugin/frontend/l10n directories on a copy of the unzipped release tree (or directly on a live
device install), relaunch, confirm no crash / no missing-module `InfoMessage` from the patch
system, confirm file manager and text editor still work. Repeat until the list is stable, then
encode it into `overlay/koreader/prune/*` and `build.sh`.

**Smoke test (full build):**
1. App boots straight to the file manager (never the reader) — same as today.
2. New file / Save as still work (existing patches, unchanged).
3. Language menu (Settings) lists only English/French/Italian/German/Spanish.
4. On-screen keyboard offers only EFIGS input layouts, matching the language menu.
5. A paired Bluetooth keyboard produces correct characters for each of the five layouts,
   including Shift and AltGr levels (accented characters, layout-specific punctuation).
6. Alt+Left/Right moves the cursor by word; Cmd/Meta+Left/Right moves it to line start/end.
   Plain arrows, Backspace, Home/End, and Ctrl-combos still work unchanged (delegated to the
   original, as today).
7. No reader/PDF/EPUB entry point is reachable anywhere in the UI; no pruned plugin's menu
   entry appears.

## Risks & limitations

- **Plugin interdependencies are not always obvious from directory names.** A "non-notepad"
  plugin might still be `require`d by kept code (event bus registrations, shared utility
  modules). Mitigated by empirical validation (relaunch-and-check) before finalizing the prune
  list, not by static assumption.
- **Meta/Super key naming from a generic BT keyboard is unverified.** Unlike Shift/AltGr
  (already handled), the stock event map's handling of the Meta/Super key at the pinned
  `KO_VERSION` needs checking the same way `;`/`-`/`=`/etc. needed a fix for the printable case.
- **The compiled binary's size is unchanged.** This branch makes the *application* smaller and
  simpler, not the shipped executable — see Non-goals.
- **l10n/keyboard-layout folder naming conventions** (e.g. `en` vs `en_US`, `es` vs
  `es_ES`) need confirming against the actual pinned release tree before the keep-list is
  final.

## Out of scope (future, own cycles)

Shrinking the compiled binary via a real source fork (Approach B), wireless/cloud export in any
form, non-Latin scripts / dead-key composition, physical d-pad support.
