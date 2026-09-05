# OkayWrite — Trimmed writing interface + correct keyboard input (design)

**Date:** 2026-09-05  
**Status:** Draft for review  
**Repo:** okaykoa/OkayWrite

## Context & goal

OkayWrite is a writing app for jailbroken Kindles implemented as a thin **overlay** on stock
KOReader — no fork, no compile; it ships KOReader's prebuilt binary and layers Lua
*userpatches* (`koreader/patches/`). Today the single patch `2-okaywrite.lua` flips settings
so `.txt`/`.md` open in the Text editor, the file browser boots into `/mnt/us/OkayWrite`, and
the app starts in the file manager.

This design adds exactly **three** features and changes nothing else in KOReader (no lockdown
of other surfaces — booting into the file manager already keeps it writing-focused):

- **A. "New file" in the file-manager "+" menu.**
- **B. "Save as" in the text editor.**
- **C. Correct physical (Bluetooth) keyboard text input** — done as a real layout layer, not the
  upstream stopgap.

Everything is delivered as `late`-phase userpatches at the pinned KOReader version
(`KO_VERSION=v2026.07.1`). All source line references below are at tag `v2026.07.1`.

## Non-goals / explicit scope lines

- No trimming/hiding of other KOReader menus, settings, or the reader.
- No Bluetooth pairing UI, helper, or bundled bridge. We **assume `kindle-hid-passthrough` is
  already installed** by the user and rely on mainline KOReader's `externalkeyboard.koplugin`
  for connection/detection. "As standard as possible."
- No wired/USB keyboard support (not a realistic Kindle path).
- Keyboard layout scope: **US + simple national layouts, with Shift and AltGr levels.**
  Explicitly out: dead keys / compose sequences, non-Latin scripts, and moving character
  composition out of the widget entirely (all genuinely upstream-scale).

## Userpatch mechanics (shared)

- Use `late` priority (filename prefix `2-`); patches run after UIManager is ready and a
  failure surfaces as an InfoMessage rather than crashing (`frontend/userpatch.lua`).
- **Core app methods** (FileManager, InputText): `require` the module, save the original,
  replace/wrap the method on the class table — the singleton picks it up via its metatable.
- **Plugin methods** (texteditor): use `userpatch.registerPatchPluginFunc("texteditor", fn)` —
  plugins are re-instantiated per FileManager/Reader spin-up, so the patch must re-apply to each
  new instance (`userpatch.lua` ~L166–191).

**Patch files (in `overlay/koreader/patches/`):**

| File | Feature |
|------|---------|
| `2-okaywrite.lua` | existing — settings (providers, home dir, start_with) |
| `2-okaywrite-newfile.lua` | A — "New file" in "+" menu (+ capture texteditor instance) |
| `2-okaywrite-saveas.lua` | B — "Save as" in editor menu |
| `2-okaywrite-keyboard.lua` | C — layout table + InputText wrapper + event-map fix |

## Feature A — "New file" in the "+" menu

**Behavior:** insert a **New file** button immediately *before* the existing **New folder**
button, at its current position. The rest of the menu is untouched.

**Hook:** wrap `FileManager:getPlusDialogButtons()` (`frontend/apps/filemanager/filemanager.lua`
L531–776; "New folder" row at L674). The wrapper calls the original to get `title, buttons`,
finds the row whose button `text == _("New folder")`, and `table.insert`s a **New file** row just
above it, then returns. This avoids rebuilding the ~120-line menu (robust across updates) and
leaves the multi-select-mode menu alone.

**"New file" action:** reuse the Text editor plugin's `newFile(folder .. "/")`
(`plugins/texteditor.koplugin/main.lua` L339) — it prompts for a filename defaulting into the
current folder and opens the editor. This needs a handle to the texteditor plugin instance:
capture it via `registerPatchPluginFunc("texteditor", ...)` into an upvalue that the FileManager
wrapper closes over. Close `self.plus_dialog` before invoking.

## Feature B — "Save as" in the editor

**Behavior:** add a **Save as** entry to the editor's top-left ☰ menu (which today holds only
screen-rotation options). No always-on-screen button (that would require copying the ~165-line
`editFile` and re-verifying every update — rejected).

**Hook:** override `TextEditor:showMenu` (`main.lua` L684–709) via
`registerPatchPluginFunc("texteditor", ...)`; keep the existing rotation buttons and add a
"Save as" row.

**Save-as action:**
1. `content = self.input:getInputText()`.
2. Prompt for a new path with an `InputDialog` + "Choose folder" `PathChooser`, reusing the
   pattern in `newFile` (L339); default into the current file's folder.
3. `self:saveFileContent(new_path, content)` — `saveFileContent` (L471) already accepts an
   arbitrary path.
4. Reopen the new file for continued editing via `self:checkEditFile(new_path, false, true)`.

## Feature C — Correct physical keyboard input

### Why not the upstream stopgap
KOReader turns a scancode into a key *name* (`input.lua` L801) and the text widget guesses the
glyph from that name using hardcoded US tables, Shift-only (`inputtext.lua` `onKeyPress`
L793, compose path L922–938). PR #15999 adds a *fourth* hardcoded US `shift_symbol_map` in the
widget. It's US-only, Shift-only (no AltGr), and conflates "which key" with "which character".
Maintainers acknowledge the widget code is a hack and there is **no** blessed layout design.

### The correct model (and what we implement)
The right architecture is KOReader's own SDL model: a **layout layer resolves (key + modifier
level) → finished character** and the widget just inserts text (`sdl/device.lua` L352 emits a
pre-composed `TextInput`; `inputtext.lua` `onTextInput` L948 just `addChars`). The *full* form
(emit `TextInput` from the evdev boundary, remove composition from the widget, add a layout
picker) is upstream-scale.

For OkayWrite we implement the correct **abstraction** in overlay-friendly form:

1. **A real layout table** keyed by `(key_name, level)` where `level ∈ {base, shift, altgr,
   shift_altgr}` → produced UTF-8 string. Start with a complete US-QWERTY layout; structured so
   other simple layouts are drop-in.
2. **Wrap `InputText:onKeyPress`** (do not replace): in the wrapper, handle **only** the
   printable case — focused, `not Device:isSDL()`, single-character key, modifiers ⊆ {Shift,
   AltGr} — by resolving via the layout table and calling `self:addChars(resolved); return
   true`. **Delegate everything else** (Backspace, arrows, Home/End, Ctrl-combos, Sym,
   navigation, screenshot) to the saved original. No large function is copied.
3. **Normalize the event map on keyboard connect.** The stock `event_map_keyboard.lua` at
   v2026.07.1 mislabels `;` and omits `-`, `=`, `[`, `]`, backtick, starving those keys of a
   name. Re-merge corrected names into `Device.input.event_map` on the
   `PhysicalKeyboardConnected` event (`externalkeyboard.koplugin/main.lua` L442) so the layout
   table has distinct keys to resolve.

AltGr works because `RAlt` is a tracked modifier; the wrapper handles the printable case before
the stock "any non-Shift modifier → don't insert" early-return, so AltGr levels are reachable.

### Standard pieces we rely on (not re-implemented)
- `kindle-hid-passthrough` (user-installed) creates the `/dev/input/eventX` node.
- Mainline `externalkeyboard.koplugin` detects the keyboard, flips capability flags, and routes
  key events. **Verify** the pinned KOReader build includes the Kindle enabler (PR #15248,
  merged 2026-05-01 — in July release) and the crash-with-connected-keyboard fix (#15681,
  merged 2026-07-15). If `v2026.07.1` predates #15681, **bump `KO_VERSION`** to a release that
  includes it.

### Upstreamability
The layout table + wrapper is deliberately structured so the same layout data and resolution
logic could later be offered upstream as the "regular patch" maintainers asked for.

## Docs & build changes

- **README:** update the roadmap — keyboard moves from "spike" to "in progress (clean layout
  patch)"; note the three features; state that BT keyboard requires `kindle-hid-passthrough`.
- **INSTALL.md:** add a short "Bluetooth keyboard" section — install `kindle-hid-passthrough`
  and pair *outside* OkayWrite; OkayWrite handles correct typing once a keyboard is connected.
- **build.sh:** bump `KO_VERSION` only if the #15681 verification requires it. No bundling, no
  `THIRD-PARTY-NOTICES` (the bridge is not redistributed).

## Verification

**Fast loop (no repackage):** copy changed patches into a running install's
`koreader/patches/`, relaunch, and confirm each patch loaded (patch-management menu / no failure
InfoMessage; keyboard patch logs on connect).

- **A:** File manager → tap **+** → "New file" appears directly above "New folder" → tap it →
  filename prompt (defaults to current folder) → creates and opens the file in the editor. Rest
  of the "+" menu unchanged.
- **B:** Open a `.txt`/`.md` → ☰ menu → "Save as" → prompt (with folder picker) → saves to the
  new path → editing continues on the new file. Original "Save" still writes the original file.
- **C (on-device, keyboard paired via the bridge):** in the editor, verify letters, Shift+letter
  (uppercase), **shifted punctuation** (`!@#$%^&*()_+{}|:"<>?~`), and AltGr levels if the layout
  has them, all insert the correct glyph. Confirm Backspace, arrows, Home/End, and Ctrl-combos
  still work (delegated to the original). Confirm the on-screen keyboard is unaffected.

## Risks & limitations

- **Firmware 5.19.6 is very new** and untested with the bridge; the bridge/connection layer is
  the user's responsibility, but flaky reconnect/sleep and Wi-Fi-vs-BT chip contention are known
  KOReader/MTK issues to watch during verification.
- **Layout scope** is Latin US + simple layouts; dead keys/compose and non-Latin are out.
- **Wrapping `InputText:onKeyPress`** is robust but still a monkeypatch — re-check on any
  `KO_VERSION` bump that the printable-case boundary and event names still hold.

## Out of scope (future, own cycles)

Upstreaming the full layout layer (`TextInput` at the input boundary + picker UI), non-Latin /
dead-key support, any KOReader stripping, and wireless/QR export.
