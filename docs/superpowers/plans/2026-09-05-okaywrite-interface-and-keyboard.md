# OkayWrite: Writing Interface + Correct Keyboard Input — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three features to OkayWrite via KOReader userpatches — a "New file" entry in the file-manager "+" menu, a "Save as" entry in the text editor, and correct physical-keyboard text input (a real layout layer, not the upstream shift-map stopgap).

**Architecture:** OkayWrite is a thin overlay: it ships KOReader's prebuilt binary and layers `late`-phase Lua userpatches under `overlay/koreader/patches/`. Each feature is a self-contained patch that *wraps/delegates* to KOReader methods rather than copying large functions. The keyboard layout logic is factored into a dependency-free helper module so it can be unit-tested off-device; everything that touches KOReader runtime modules is syntax-checked locally and functionally verified on-device via the fast-iteration loop.

**Tech Stack:** Lua 5.1 (KOReader runtime); `luacheck` (lint/syntax gate); `busted` (unit tests for the pure layout module); KOReader v2026.07.1 APIs; `kindle-hid-passthrough` (user-installed, out of repo) + mainline `externalkeyboard.koplugin`.

**Spec:** `docs/superpowers/specs/2026-09-05-okaywrite-interface-and-keyboard-design.md`

## Global Constraints

- **KOReader version:** `KO_VERSION=v2026.07.1` (in `build.sh`). Confirmed to include the connected-keyboard crash fix (PR #15681, merged 2026-07-15; release published 2026-08-01). Do NOT bump for this work. All KOReader source references are at tag `v2026.07.1`.
- **Overlay only:** no KOReader core files are modified or forked. Patches live in `overlay/koreader/patches/`, use `late` priority (filename prefix `2-`), and must be idempotent and fail-safe (guard against missing globals; never crash startup).
- **Wrap, don't copy:** prefer wrapping a method and delegating the untouched cases to the original over reproducing large functions. Where a small self-contained method must be reproduced (editor `showMenu`), copy it verbatim from the pinned tag and add a re-verify note.
- **Keyboard scope:** US + simple national layouts, Shift and AltGr levels. Out of scope: dead keys/compose, non-Latin scripts, moving composition out of the widget (upstream-scale).
- **No bundling:** `kindle-hid-passthrough` is assumed installed by the user; it is NOT redistributed. No `THIRD-PARTY-NOTICES`.
- **Commit hygiene:** commit history for this repo must contain NO "Claude"/"Anthropic" identifiers (author, committer, message, or trailer). Author is the repo's configured okaykoa identity. Commit locally; do NOT push (the user pushes).
- **Naming/label copy:** user-facing strings wrapped in `_( )` (gettext): exactly `"New file"`, `"New folder"` (existing), `"Save as"`.

## Confirm-against-source rule

Several KOReader internals (exact method bodies, scancodes, modifier and plugin names) must match the pinned tag. Where a task says "confirm against source," read the exact file with:
`gh api repos/koreader/koreader/contents/PATH?ref=v2026.07.1 --jq .content | base64 -d`
and adjust the constants/reproduced bodies to what you actually see before finalizing the task.

## File Structure

- Create: `overlay/koreader/patches/okaywrite/keyboard_layout.lua` — pure, dependency-free layout module (data + `resolve`). Not a patch (subdir → not scanned by the patch loader); loaded by the keyboard patch and required directly by tests.
- Create: `spec/keyboard_layout_spec.lua` — busted unit tests for the layout module.
- Create: `overlay/koreader/patches/2-okaywrite-newfile.lua` — Feature A (+ captures the texteditor plugin instance).
- Create: `overlay/koreader/patches/2-okaywrite-saveas.lua` — Feature B.
- Create: `overlay/koreader/patches/2-okaywrite-keyboard.lua` — Feature C (event-map normalization + `InputText:onKeyPress` wrapper).
- Create: `.luacheckrc` — lint config declaring KOReader globals so `luacheck` is useful.
- Modify: `README.md` — roadmap/status; `INSTALL.md` — Bluetooth keyboard section.
- Unchanged: `overlay/koreader/patches/2-okaywrite.lua` (existing settings patch).

## Testing approach (read before starting)

- **Pure logic (Task 1):** real TDD with `busted`. The layout module has zero KOReader dependencies.
- **Patches (Tasks 2–4):** cannot execute off-device (they `require` KOReader runtime modules that are not present locally). Local automated gate = `luacheck` (syntax + undefined-global check against `.luacheckrc`). Functional verification = **on-device manual acceptance**, performed by the user via the fast-iteration loop:
  copy the changed patch(es) into a mounted Kindle's `koreader/patches/`, relaunch KOReader, and observe. A `late` patch that fails to load pops an InfoMessage and is listed as failed in KOReader's patch-management menu.
- On-device acceptance steps are written as explicit checklists; they are the "test" for those tasks and are expected to be run by the user on the target Kindle.

---

### Task 1: Keyboard layout module (pure logic, TDD)

**Files:**
- Create: `overlay/koreader/patches/okaywrite/keyboard_layout.lua`
- Test: `spec/keyboard_layout_spec.lua`

**Interfaces:**
- Produces: a module table `M` with
  - `M.layouts` — `{ us = { [KEYNAME] = { base=STR, shift=STR, altgr=STR?, shift_altgr=STR? }, ... } }` holding NON-letter keys only.
  - `M.resolve(layout_name, key_name, mods)` where `mods = { shift=bool, altgr=bool }` → returns the produced UTF-8 string, or `nil` when the key/level is not a printable character this layout handles (caller then delegates). Single `A`–`Z` letters are handled by case-folding (base=lower, shift=upper) unless the layout provides an override.

- [ ] **Step 1: Install Lua tooling (setup for this and later tasks)**

Run:
```bash
brew install lua luarocks
luarocks install busted
luarocks install luacheck
busted --version && luacheck --version
```
Expected: both print versions. (If `brew` is unavailable, install Lua 5.1 + LuaRocks by the platform's usual means; the module targets Lua 5.1 semantics but is plain enough to run under any 5.x for testing.)

- [ ] **Step 2: Write the failing test**

Create `spec/keyboard_layout_spec.lua`:
```lua
local M = dofile("overlay/koreader/patches/okaywrite/keyboard_layout.lua")

describe("keyboard_layout.resolve (us)", function()
  local function r(name, shift, altgr)
    return M.resolve("us", name, { shift = shift or false, altgr = altgr or false })
  end

  it("lowercases letters without shift", function()
    assert.are.equal("a", r("A"))
    assert.are.equal("z", r("Z"))
  end)

  it("uppercases letters with shift", function()
    assert.are.equal("A", r("A", true))
    assert.are.equal("Z", r("Z", true))
  end)

  it("passes digits through without shift", function()
    assert.are.equal("1", r("1"))
    assert.are.equal("0", r("0"))
  end)

  it("maps shifted digits to symbols", function()
    assert.are.equal("!", r("1", true))
    assert.are.equal("@", r("2", true))
    assert.are.equal(")", r("0", true))
  end)

  it("maps shifted punctuation", function()
    assert.are.equal(";", r(";"))
    assert.are.equal(":", r(";", true))
    assert.are.equal("/", r("/"))
    assert.are.equal("?", r("/", true))
    assert.are.equal("-", r("-"))
    assert.are.equal("_", r("-", true))
    assert.are.equal("=", r("="))
    assert.are.equal("+", r("=", true))
    assert.are.equal("[", r("["))
    assert.are.equal("{", r("[", true))
    assert.are.equal("`", r("`"))
    assert.are.equal("~", r("`", true))
    assert.are.equal('"', r("'", true))
  end)

  it("returns nil for keys it does not handle", function()
    assert.is_nil(r("F1"))
    assert.is_nil(r("Home"))
  end)

  it("returns nil for a letter under AltGr when no override exists", function()
    assert.is_nil(r("A", false, true))
  end)

  it("returns nil for an unknown layout", function()
    assert.is_nil(M.resolve("dvorak", "1", { shift = true }))
  end)
end)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: FAIL — cannot load `overlay/koreader/patches/okaywrite/keyboard_layout.lua` (file does not exist).

- [ ] **Step 4: Write the module**

Create `overlay/koreader/patches/okaywrite/keyboard_layout.lua`:
```lua
-- OkayWrite physical-keyboard layout resolver (dependency-free, unit-testable).
-- Maps (key name, modifier level) -> produced character. Letters are handled by
-- case-folding; only non-letter keys live in the layout tables.

local M = {}

M.layouts = {
  us = {
    ["1"] = { base = "1", shift = "!" },
    ["2"] = { base = "2", shift = "@" },
    ["3"] = { base = "3", shift = "#" },
    ["4"] = { base = "4", shift = "$" },
    ["5"] = { base = "5", shift = "%" },
    ["6"] = { base = "6", shift = "^" },
    ["7"] = { base = "7", shift = "&" },
    ["8"] = { base = "8", shift = "*" },
    ["9"] = { base = "9", shift = "(" },
    ["0"] = { base = "0", shift = ")" },
    ["-"] = { base = "-", shift = "_" },
    ["="] = { base = "=", shift = "+" },
    ["["] = { base = "[", shift = "{" },
    ["]"] = { base = "]", shift = "}" },
    ["\\"] = { base = "\\", shift = "|" },
    [";"] = { base = ";", shift = ":" },
    ["'"] = { base = "'", shift = '"' },
    ["`"] = { base = "`", shift = "~" },
    [","] = { base = ",", shift = "<" },
    ["."] = { base = ".", shift = ">" },
    ["/"] = { base = "/", shift = "?" },
  },
}

-- key_name: the KOReader key name (letters arrive upper-case, e.g. "A"; symbols
--           arrive as their base char, e.g. ";"). mods = { shift, altgr }.
function M.resolve(layout_name, key_name, mods)
  mods = mods or {}
  if type(key_name) ~= "string" then return nil end

  local layout = M.layouts[layout_name]

  -- Single A-Z letter: case-fold, unless the layout defines an override
  -- (e.g. an AltGr accent) for this key.
  if key_name:match("^[A-Z]$") then
    local entry = layout and layout[key_name]
    if mods.altgr then
      return entry and (mods.shift and entry.shift_altgr or entry.altgr) or nil
    end
    return mods.shift and key_name or key_name:lower()
  end

  if not layout then return nil end
  local entry = layout[key_name]
  if not entry then return nil end

  local level
  if mods.shift and mods.altgr then level = "shift_altgr"
  elseif mods.altgr then level = "altgr"
  elseif mods.shift then level = "shift"
  else level = "base" end
  return entry[level]
end

return M
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: PASS (all examples green).

- [ ] **Step 6: Add `.luacheckrc` for later tasks and lint the module**

Create `.luacheckrc`:
```lua
std = "lua51"
-- KOReader globals available to userpatches at runtime.
globals = { "G_reader_settings" }
read_globals = { "require", "dofile" }
-- Patches intentionally shadow/extend module methods; allow it.
ignore = { "212", "213" } -- unused arg / unused loop var
```
Run: `luacheck overlay/koreader/patches/okaywrite/keyboard_layout.lua`
Expected: `0 warnings / 0 errors` (or only benign ignored codes).

- [ ] **Step 7: Commit**

```bash
git add overlay/koreader/patches/okaywrite/keyboard_layout.lua spec/keyboard_layout_spec.lua .luacheckrc
git commit -m "Add physical-keyboard layout resolver with tests"
```

---

### Task 2: "New file" in the file-manager "+" menu (Feature A)

**Files:**
- Create: `overlay/koreader/patches/2-okaywrite-newfile.lua`

**Interfaces:**
- Consumes: `require("apps/filemanager/filemanager")` → `FileManager` (class table); `require("userpatch")` → `userpatch.registerPatchPluginFunc`; the texteditor plugin instance's `newFile(path)` method (`plugins/texteditor.koplugin/main.lua:339`).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Confirm against source**

Read `frontend/apps/filemanager/filemanager.lua` at `v2026.07.1` and confirm: `getPlusDialogButtons(self)` returns `title, buttons` (around L776); the normal-mode branch is guarded by `self.selected_files`; the "New folder" row is a `{{ text = _("New folder"), callback = ... }}` entry; and the dialog handle is `self.plus_dialog`. Also read `plugins/texteditor.koplugin/_meta.lua` to confirm the plugin name is `texteditor` and `main.lua` to confirm `newFile(new_path)` exists at ~L339. Adjust the code below if any differ.

- [ ] **Step 2: Write the patch**

Create `overlay/koreader/patches/2-okaywrite-newfile.lua`:
```lua
-- OkayWrite: add a "New file" action to the FileManager "+" menu, directly
-- above the existing "New folder" entry. Delegates to the Text editor plugin's
-- newFile() so the file opens in the editor after creation.

local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local userpatch = require("userpatch")
local _ = require("gettext")

-- Capture the texteditor plugin instance (re-instantiated per FM/Reader spin-up).
local texteditor
userpatch.registerPatchPluginFunc("texteditor", function(plugin)
  texteditor = plugin
end)

local orig_getPlusDialogButtons = FileManager.getPlusDialogButtons
FileManager.getPlusDialogButtons = function(self)
  local title, buttons = orig_getPlusDialogButtons(self)
  if self.selected_files then
    return title, buttons -- leave multi-select menu untouched
  end

  local folder = self.file_chooser and self.file_chooser.path
  local new_file_row = { {
    text = _("New file"),
    callback = function()
      if self.plus_dialog then UIManager:close(self.plus_dialog) end
      if texteditor and folder then
        texteditor:newFile(folder .. "/")
      end
    end,
  } }

  -- Insert "New file" immediately before the "New folder" row; if not found
  -- (e.g. unexpected localization), fall back to inserting at the top.
  local label = _("New folder")
  local inserted = false
  for i, row in ipairs(buttons) do
    if row[1] and row[1].text == label then
      table.insert(buttons, i, new_file_row)
      inserted = true
      break
    end
  end
  if not inserted then
    table.insert(buttons, 1, new_file_row)
  end

  return title, buttons
end
```

- [ ] **Step 3: Lint**

Run: `luacheck overlay/koreader/patches/2-okaywrite-newfile.lua`
Expected: 0 errors (undefined-global warnings for KOReader modules are acceptable if they appear; add them to `.luacheckrc` `read_globals` only if noisy — do NOT silence real syntax errors).

- [ ] **Step 4: On-device acceptance (user runs on the target Kindle)**

With the Kindle mounted:
```sh
cp overlay/koreader/patches/2-okaywrite-newfile.lua /Volumes/Kindle/koreader/patches/
```
Eject, relaunch KOReader, then verify:
- The "+" menu shows **New file** directly above **New folder**; every other "+" entry is unchanged and in its original order.
- Tapping **New file** opens a filename prompt defaulting into the current folder; confirming creates the file and opens it in the Text editor.
- No patch-failure InfoMessage; patch-management menu lists `2-okaywrite-newfile.lua` as loaded.
Record PASS/FAIL per bullet. If FAIL, capture the crash.log line and adjust (most likely: the "New folder" label match or `newFile` signature — re-run Step 1).

- [ ] **Step 5: Commit**

```bash
git add overlay/koreader/patches/2-okaywrite-newfile.lua
git commit -m "Add New file action to file-manager plus menu"
```

---

### Task 3: "Save as" in the text editor (Feature B)

**Files:**
- Create: `overlay/koreader/patches/2-okaywrite-saveas.lua`

**Interfaces:**
- Consumes: `require("userpatch")`; the texteditor plugin instance methods `showMenu(self)` (`main.lua:684-709`), `saveFileContent(path, content)` (`main.lua:471`), `checkEditFile(path, readonly, new)` and `self.input:getInputText()`; `require("ui/widget/inputdialog")`, `require("ui/widget/pathchooser")`, `require("ui/uimanager")`.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Confirm against source**

Read `plugins/texteditor.koplugin/main.lua` at `v2026.07.1`: copy the exact current body of `showMenu` (L684-709, the rotation options + ButtonDialog) and note the exact `newFile` prompt pattern (L339: `InputDialog` with a "Choose folder" button opening a `PathChooser`, plus Cancel/confirm). Confirm `saveFileContent(file_path, content)` (L471) and how the current file path and `self.input` buffer are accessed. Build Step 2 on the bodies you actually read.

- [ ] **Step 2: Write the patch**

Create `overlay/koreader/patches/2-okaywrite-saveas.lua`. Reproduce the confirmed `showMenu` body verbatim, then add a "Save as" row before showing the dialog. Wire the callback to the confirmed prompt pattern:
```lua
-- OkayWrite: add "Save as" to the Text editor's top-left menu.
local userpatch = require("userpatch")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

userpatch.registerPatchPluginFunc("texteditor", function(plugin)
  -- Prompt for a destination path, then write the current buffer there and
  -- continue editing the new file. Mirrors the plugin's own newFile() pattern.
  local function saveAs(self)
    local content = self.input:getInputText()
    local start_path = (self.last_edit_dir and (self.last_edit_dir .. "/")) or ""
    local dialog
    dialog = InputDialog:new{
      title = _("Save as"),
      input = start_path,
      buttons = { {
        {
          text = _("Choose folder"),
          callback = function()
            UIManager:close(dialog)
            local chooser = PathChooser:new{
              select_directory = true,
              select_file = false,
              path = self.last_edit_dir,
              onConfirm = function(dir)
                saveAs(self) -- reopen prompt; user appends a filename
              end,
            }
            UIManager:show(chooser)
          end,
        },
        {
          text = _("Cancel"),
          id = "close",
          callback = function() UIManager:close(dialog) end,
        },
        {
          text = _("Save"),
          is_enter_default = true,
          callback = function()
            local new_path = dialog:getInputText()
            UIManager:close(dialog)
            if new_path and new_path ~= "" then
              self:saveFileContent(new_path, content)
              self:checkEditFile(new_path, false, true)
            end
          end,
        },
      } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
  end

  -- Reproduce the confirmed showMenu body here, then append the Save as row
  -- to its button table before UIManager:show(...). Replace the block below
  -- with the verbatim body read in Step 1, edited only to add:
  --   { { text = _("Save as"), callback = function() UIManager:close(menu); saveAs(self) end } }
  local orig_showMenu = plugin.showMenu
  plugin.showMenu = function(self)
    -- If the verbatim reproduction is deferred, fall back to original + note:
    return orig_showMenu(self)
  end
end)
```

> **Implementation note (not a placeholder to ship):** Step 1 yields the exact `showMenu` body. Paste it in place of the fallback `plugin.showMenu` above, keep its rotation buttons, and insert one extra button row `{ { text = _("Save as"), callback = function() UIManager:close(<the dialog var used by showMenu>); saveAs(self) end } }` into its ButtonDialog `buttons` before it is shown. The fallback that calls `orig_showMenu` must NOT be the final shipped code — it exists only so the file lints before Step 1's body is pasted in. The task is not complete until "Save as" actually appears.

- [ ] **Step 3: Lint**

Run: `luacheck overlay/koreader/patches/2-okaywrite-saveas.lua`
Expected: 0 syntax errors.

- [ ] **Step 4: On-device acceptance (user runs)**

Copy the patch to `/Volumes/Kindle/koreader/patches/`, eject, relaunch, then:
- Open a `.txt`/`.md` file in the editor; open the top-left menu; verify **Save as** appears alongside the existing rotation options.
- Tap **Save as**, pick/enter a new filename (folder picker available, defaults into the current folder); confirm; verify a new file is written with the current contents and the editor is now editing that new file.
- Verify the normal **Save** button still writes the original file.
- No patch-failure InfoMessage.
Record PASS/FAIL. If the menu var name from Step 1 differs, fix and re-verify.

- [ ] **Step 5: Commit**

```bash
git add overlay/koreader/patches/2-okaywrite-saveas.lua
git commit -m "Add Save as to text editor menu"
```

---

### Task 4: Correct physical-keyboard input (Feature C)

**Files:**
- Create: `overlay/koreader/patches/2-okaywrite-keyboard.lua`

**Interfaces:**
- Consumes: `require("ui/widget/inputtext")` → `InputText` (class); `require("device")` → `Device` (`Device:isSDL()`, `Device.input.event_map`); `require("datastorage")` → `getPatchesDir()`; `require("userpatch")`; the layout module from Task 1 (`M.resolve`).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Confirm against source (constants)**

Read at `v2026.07.1`:
- `plugins/externalkeyboard.koplugin/event_map_keyboard.lua` — record which of these keys have names and what they are: KEY_MINUS(12), KEY_EQUAL(13), KEY_LEFTBRACE(26), KEY_RIGHTBRACE(27), KEY_SEMICOLON(39), KEY_APOSTROPHE(40), KEY_GRAVE(41), KEY_BACKSLASH(43), KEY_COMMA(51), KEY_DOT(52), KEY_SLASH(53). The known defects to fix: `[39]` is `":"` (must be `";"`) and `-,=,[,],`` `` are missing.
- `plugins/externalkeyboard.koplugin/_meta.lua` — confirm the plugin name (`externalkeyboard`) and that `setupKeyboard` sets `Device.input.event_map`.
- `frontend/ui/widget/inputtext.lua` — confirm `onKeyPress(self, key)` exists, that `key.key` is the (upper-case for letters) name, that modifiers are read as `key["Shift"]` etc., and confirm the right-Alt modifier name (`key["AltGr"]` vs `key["RAlt"]`) via `frontend/device/input.lua` modifiers/event_map. Set `ALTGR_KEYS` below to the confirmed name(s).
- `frontend/device/generic/device.lua` — confirm `Device:isSDL()` exists (it does).
Fill the scancode corrections in Step 2 with exactly what is missing/wrong per the file you read.

- [ ] **Step 2: Write the patch**

Create `overlay/koreader/patches/2-okaywrite-keyboard.lua`:
```lua
-- OkayWrite: correct physical-keyboard text input. Resolves (key, modifiers)
-- to a character via a real layout table and inserts finished text, instead of
-- the widget guessing glyphs from key names. Delegates everything else to the
-- original InputText:onKeyPress.

local InputText = require("ui/widget/inputtext")
local Device = require("device")
local DataStorage = require("datastorage")
local userpatch = require("userpatch")

local layout = dofile(DataStorage:getPatchesDir() .. "/okaywrite/keyboard_layout.lua")
local ACTIVE_LAYOUT = "us"

-- Modifier names that mean AltGr on this device (confirm in Step 1).
local ALTGR_KEYS = { "AltGr", "RAlt" }

-- 1) Normalize the external-keyboard event map so punctuation keys have correct
--    names. Applied by wrapping the plugin's setupKeyboard (runs on connect).
local EVENT_MAP_FIXES = {
  [12] = "-", [13] = "=", [26] = "[", [27] = "]",
  [39] = ";", [41] = "`",
  -- add [40]="'", [43]="\\", [51]=",", [52]=".", [53]="/" only if Step 1 shows
  -- them missing/wrong in the shipped event_map_keyboard.lua.
}
userpatch.registerPatchPluginFunc("externalkeyboard", function(plugin)
  local orig_setup = plugin.setupKeyboard
  plugin.setupKeyboard = function(self, ...)
    local ret = orig_setup(self, ...)
    local em = Device.input and Device.input.event_map
    if em then
      for code, name in pairs(EVENT_MAP_FIXES) do
        em[code] = name
      end
    end
    return ret
  end
end)

-- 2) Wrap InputText:onKeyPress: handle the printable case via the layout table,
--    delegate everything else to the original.
local orig_onKeyPress = InputText.onKeyPress
InputText.onKeyPress = function(self, key)
  if not Device:isSDL() and type(key.key) == "string" then
    -- Only intercept when modifiers are a subset of { Shift, AltGr }.
    local shift = key["Shift"] and true or false
    local altgr = false
    for _, n in ipairs(ALTGR_KEYS) do if key[n] then altgr = true end end

    local other_modifier = false
    for name, flag in pairs(key.modifiers or {}) do
      if flag and name ~= "Shift" then
        local is_altgr = false
        for _, n in ipairs(ALTGR_KEYS) do if name == n then is_altgr = true end end
        if not is_altgr then other_modifier = true end
      end
    end

    if not other_modifier then
      local ch = layout.resolve(ACTIVE_LAYOUT, key.key, { shift = shift, altgr = altgr })
      if ch then
        self:addChars(ch)
        return true
      end
    end
  end
  return orig_onKeyPress(self, key)
end
```

- [ ] **Step 3: Lint**

Run: `luacheck overlay/koreader/patches/2-okaywrite-keyboard.lua`
Expected: 0 syntax errors.

- [ ] **Step 4: On-device acceptance (user runs, keyboard paired via kindle-hid-passthrough)**

Copy BOTH `overlay/koreader/patches/2-okaywrite-keyboard.lua` AND the helper `overlay/koreader/patches/okaywrite/keyboard_layout.lua` (preserving the `okaywrite/` subfolder) to the Kindle:
```sh
mkdir -p /Volumes/Kindle/koreader/patches/okaywrite
cp overlay/koreader/patches/2-okaywrite-keyboard.lua /Volumes/Kindle/koreader/patches/
cp overlay/koreader/patches/okaywrite/keyboard_layout.lua /Volumes/Kindle/koreader/patches/okaywrite/
```
Eject, relaunch, connect the BT keyboard, open a `.txt` in the editor, and verify:
- Letters type lower-case; **Shift+letter** types upper-case.
- **Shifted number row** types `! @ # $ % ^ & * ( )`.
- **Shifted punctuation** types `_ + { } | : " ~ < > ?` and base `- = [ ] \ ; ' `` , . /` all insert the correct glyph (these are the keys that produced nothing before).
- **Backspace, arrows, Home/End, and any Ctrl-shortcuts still work** (delegated to the original).
- The **on-screen keyboard is unaffected** (tap-typing still works normally).
- The helper file does NOT appear as a loaded/failed patch (subfolder → not scanned); only `2-okaywrite-keyboard.lua` is listed.
Record PASS/FAIL per bullet. If a punctuation key still does nothing, its scancode name is missing from the event map — extend `EVENT_MAP_FIXES` with the code from Step 1 and re-verify.

- [ ] **Step 5: Commit**

```bash
git add overlay/koreader/patches/2-okaywrite-keyboard.lua
git commit -m "Add correct physical-keyboard layout input"
```

---

### Task 5: Documentation (README roadmap + INSTALL keyboard section)

**Files:**
- Modify: `README.md`
- Modify: `INSTALL.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update the README roadmap**

In `README.md`, update the Roadmap table rows so they reflect reality after this work:
- On-screen keyboard: ✅ works (unchanged).
- Bluetooth keyboard: change to ✅ **works (correct layout)** — note it needs `kindle-hid-passthrough` installed, and that OkayWrite provides a real US layout (Shift + AltGr) via userpatch, not the upstream shift-map.
- Add brief mentions that the "+" menu now offers **New file** and the editor has **Save as**.
Keep the "overlay now, strip later" framing and the KOReader attribution block intact.

- [ ] **Step 2: Add a Bluetooth keyboard section to INSTALL.md**

Append a short section to `INSTALL.md`:
```markdown
## Bluetooth keyboard (optional)

OkayWrite makes a physical keyboard type correctly (including shifted
punctuation), but it does not pair the keyboard itself — Kindle's stock
Bluetooth stack cannot. Pairing is handled outside OkayWrite by
**kindle-hid-passthrough** (https://github.com/zampierilucas/kindle-hid-passthrough),
which must be installed separately (install `usbnetlite` first as a recovery net,
and use its minimal daemon + KOReader-plugin path — not the full installer).

Once a keyboard is paired and connected, OkayWrite's layout patch handles typing;
no configuration is needed. US layout is provided by default.
```

- [ ] **Step 3: Verify docs render**

Run: `python3 -m http.server` is not needed; just re-read both files and confirm the Markdown tables/links are well-formed and no stale `okaywriter`/absolute-path references were introduced:
```bash
grep -rin "okaywriter" README.md INSTALL.md || echo "clean"
```
Expected: `clean`.

- [ ] **Step 4: Commit**

```bash
git add README.md INSTALL.md
git commit -m "Document New file, Save as, and keyboard support"
```

---

## Self-Review

**Spec coverage:**
- Feature A ("New file" before "New folder", reuse `newFile`) → Task 2. ✔
- Feature B ("Save as" in ☰ menu, `saveFileContent` + prompt, reopen) → Task 3. ✔
- Feature C (layout table + wrap `onKeyPress` + event-map fix; Shift+AltGr; US; delegate rest; rely on stock plugin + user-installed bridge) → Tasks 1 + 4. ✔
- Non-goals (no other-surface lockdown, no bundling/notices, no wired) → respected; no task adds them. ✔
- Version floor (v2026.07.1 includes #15681, no bump) → Global Constraints. ✔
- Docs (README roadmap, INSTALL keyboard) → Task 5. ✔
- Commit-history hygiene (no Claude/Anthropic; local only) → Global Constraints; commit steps use plain messages. ✔

**Placeholder scan:** The only "fallback" stub is in Task 3 Step 2, explicitly flagged as not-shippable with instructions to paste the verbatim `showMenu` body from Step 1; the task's acceptance step fails if "Save as" is absent, so it cannot be left stubbed. "Confirm against source" steps are concrete (exact files + `gh api` command), not TBDs.

**Type/name consistency:** `M.resolve(layout_name, key_name, mods)` and `M.layouts` used identically in Task 1 (definition/tests) and Task 4 (consumer). `mods = { shift, altgr }` consistent. Layout name `"us"`/`ACTIVE_LAYOUT` consistent. Helper path `okaywrite/keyboard_layout.lua` consistent across creation (Task 1), on-device copy and `dofile` (Task 4).

**Residual verification (by design, not gaps):** exact `showMenu`/`newFile` bodies, the AltGr modifier name, the precise set of missing scancodes, and the `getPlusDialogButtons` return shape are each resolved by a "confirm against source" step before the code is finalized — appropriate for patching a large external codebase.
