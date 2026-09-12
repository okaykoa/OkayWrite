# Notepad-Trim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OkayWrite's shipped Kindle app actually just a notepad — prune non-notepad plugins and non-EFIGS localization/keyboard data at build time, add French/Italian/German/Spanish physical-keyboard support, and add terminal-style Alt/Cmd+arrow word/line cursor movement.

**Architecture:** `build.sh` already unzips a pinned KOReader Kindle release and layers Lua userpatches on top (`overlay/koreader/patches/`). This plan adds a prune step to that pipeline (delete non-notepad plugins, non-EFIGS `l10n/`, non-EFIGS on-screen-keyboard-layout files), a new patch that shrinks two hardcoded menu tables (language, keyboard-layout) and removes the file manager's "Cloud storage" entry, extends the existing physical-keyboard layout resolver (`okaywrite/keyboard_layout.lua`) with fr/de/it/es data, and extends the existing `InputText:onKeyPress` wrapper with Alt/Cmd+arrow word/line movement. No cross-compilation; no changes to the compiled `koreader` binary.

**Tech Stack:** Lua (KOReader userpatches + plugin), Bash (`build.sh`), `busted` (existing Lua test framework, see `spec/keyboard_layout_spec.lua`).

**Spec:** `docs/superpowers/specs/2026-09-12-notepad-trim-design.md`

## Global Constraints

- Kindle only. Pinned KOReader release: `KO_VERSION=v2026.07.1` (in `build.sh`).
- Localization limited to EFIGS: English (untranslated source strings, KOReader's `"C"` locale), French (`fr`), Italian (`it_IT`), German (`de`), Spanish (`es`). No separate `"en"` locale exists upstream.
- No dead keys / compose sequences, no non-Latin scripts (inherited from the existing keyboard-layout spec's scope line). Concretely: Spanish `á é í ó ú` are not reachable via physical keyboard in this plan (real Spanish hardware needs a dead-key compose sequence for them) — only `ñ`, `¡`, `¿` and punctuation are in scope.
- No physical d-pad hardware support. "Terminal-style Alt/Cmd+arrow movement" means a Bluetooth keyboard's own Alt/Cmd modifier held with its own arrow keys.
- No cross-compilation, no changes to the compiled `koreader` binary/MuPDF/CRengine.
- The reader app (`frontend/apps/reader/`) and PDF/EPUB engine stay physically present but unreachable through normal use (same as today's OkayWrite baseline) — confirmed during design that `frontend/apps/filemanager/filemanager.lua` has hard load-time dependencies on `apps/reader/modules/{readerdevicestatus,readerdictionary,readerwikipedia}` plus lazy dependencies on the full `ReaderUI` class, so it cannot be safely deleted in this pass.
- AltGr (Right-Alt) is **not** reliably trackable as a held modifier on this KOReader version (pre-existing, documented gap in `2-okaywrite-keyboard.lua`) — this plan does not add any AltGr-only characters, so this gap doesn't block anything here.

---

## Task 1: Let a physical-keyboard layout override a letter position

**Files:**
- Modify: `overlay/koreader/patches/okaywrite/keyboard_layout.lua`
- Test: `spec/keyboard_layout_spec.lua`

**Interfaces:**
- Consumes: nothing new.
- Produces: `M.resolve(layout_name, key_name, mods)` — unchanged signature and behavior for existing callers, but a layout entry now applies to letter key names too (needed by Tasks 2-3 for AZERTY/QWERTZ letter repositioning). `M.layouts[layout_name][key_name]` entries are `{ base, shift, altgr, shift_altgr }` as before.

Today, `M.resolve` special-cases any single A-Z `key_name` before ever consulting the layout table for it (a layout can only add an *AltGr* override for a letter, never override its base/shift value) — which means a layout can't reposition a letter (needed for French/German) or turn a letter-named position into punctuation (AZERTY's "M" key). This task makes a layout entry win outright when present, for any key name, and only falls back to case-folded identity when there's no entry at all.

- [ ] **Step 1: Install `busted` if it isn't already, then confirm the existing suite is green before refactoring**

`busted` is not bundled with this repo or preinstalled on a fresh machine (confirmed: no rockspec, no CI config, no system Lua). Install it once, then run the suite:

```bash
brew install lua luarocks   # skip if already installed
luarocks install busted
busted spec/keyboard_layout_spec.lua
```
Expected: PASS (11 successes, 0 failures) — this is the regression baseline; every one of these assertions must still pass after Step 2.

- [ ] **Step 2: Replace `M.resolve` with the entry-first version**

In `overlay/koreader/patches/okaywrite/keyboard_layout.lua`, replace the file's header comment and `M.resolve` function.

Old header (lines 1-3):
```lua
-- OkayWrite physical-keyboard layout resolver (dependency-free, unit-testable).
-- Maps (key name, modifier level) -> produced character. Letters are handled by
-- case-folding; only non-letter keys live in the layout tables.
```
New header:
```lua
-- OkayWrite physical-keyboard layout resolver (dependency-free, unit-testable).
-- Maps (key name, modifier level) -> produced character. A layout entry for a
-- key name always wins, whether that key is a letter or not; a bare A-Z key
-- with no entry falls back to case-folded identity.
```

Old function (everything from the `-- key_name:` comment down to `return M`):
```lua
-- key_name: the KOReader key name (letters arrive upper-case, e.g. "A"; symbols
--           arrive as their base char, e.g. ";"). mods = { shift, altgr }.
function M.resolve(layout_name, key_name, mods)
  mods = mods or {}
  if type(key_name) ~= "string" then return nil end

  local layout = M.layouts[layout_name]

  -- Single A-Z letter: case-fold, unless the layout defines an override
  -- (e.g. an AltGr accent) for this key. Letters are resolved independent of
  -- layout by design (only non-letter keys are layout-specific).
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
New function:
```lua
-- key_name: the KOReader key name (letters arrive upper-case, e.g. "A"; symbols
--           arrive as their base char, e.g. ";"). mods = { shift, altgr }.
--
-- A layout entry (M.layouts[layout_name][key_name]) always wins when present,
-- whether key_name is a letter or not -- this is how a layout repositions a
-- letter (e.g. AZERTY's "Q" position produces "a") or turns a US letter
-- position into punctuation (e.g. AZERTY's "M" position produces ","). With
-- no entry, a single A-Z key_name falls back to case-folded identity (the
-- "us" layout has no letter entries at all, since identity is exactly
-- correct for it already); anything else with no entry is unhandled.
function M.resolve(layout_name, key_name, mods)
  mods = mods or {}
  if type(key_name) ~= "string" then return nil end

  local layout = M.layouts[layout_name]
  local entry = layout and layout[key_name]

  if entry then
    local level
    if mods.shift and mods.altgr then level = "shift_altgr"
    elseif mods.altgr then level = "altgr"
    elseif mods.shift then level = "shift"
    else level = "base" end
    return entry[level]
  end

  if key_name:match("^[A-Z]$") then
    if mods.altgr then return nil end
    return mods.shift and key_name or key_name:lower()
  end
  return nil
end

return M
```

- [ ] **Step 3: Confirm the suite is still green after the refactor**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: PASS (11 successes, 0 failures) — identical to Step 1's baseline. If anything differs, the refactor changed observable behavior; fix before continuing.

- [ ] **Step 4: Commit**

```bash
git add overlay/koreader/patches/okaywrite/keyboard_layout.lua
git commit -m "$(cat <<'EOF'
Let a keyboard layout entry override a letter position

Needed so AZERTY/QWERTZ layouts (next) can reposition letters or turn
a US letter position into punctuation, not just add an AltGr accent
to an otherwise-identity letter. Behavior-preserving for "us".

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 2: Add the French (AZERTY) physical-keyboard layout

**Files:**
- Modify: `overlay/koreader/patches/okaywrite/keyboard_layout.lua`
- Test: `spec/keyboard_layout_spec.lua`

**Interfaces:**
- Consumes: `M.resolve` from Task 1 (entry-first behavior).
- Produces: `M.layouts.fr`, consumed later by Task 6's language→layout mapping.

- [ ] **Step 1: Write the failing tests**

Append to `spec/keyboard_layout_spec.lua` (after the existing `describe("keyboard_layout.resolve (us)", ...)` block, still inside the file, before end-of-file):

```lua
describe("keyboard_layout.resolve (fr)", function()
  local function r(name, shift, altgr)
    return M.resolve("fr", name, { shift = shift or false, altgr = altgr or false })
  end

  it("repositions letters to match AZERTY", function()
    assert.are.equal("a", r("Q"))
    assert.are.equal("A", r("Q", true))
    assert.are.equal("q", r("A"))
    assert.are.equal("z", r("W"))
    assert.are.equal("w", r("Z"))
  end)

  it("leaves non-repositioned letters untouched", function()
    assert.are.equal("e", r("E"))
    assert.are.equal("u", r("U"))
  end)

  it("produces punctuation at the repositioned M/,/. positions", function()
    assert.are.equal(",", r("M"))
    assert.are.equal("?", r("M", true))
    assert.are.equal(";", r(","))
    assert.are.equal(".", r(",", true))
  end)

  it("puts accented letters at their AZERTY base-level keys", function()
    assert.are.equal("m", r(";"))
    assert.are.equal("M", r(";", true))
    assert.are.equal("ù", r("'"))
  end)

  it("inverts the digit row (symbols unshifted, digits shifted)", function()
    assert.are.equal("&", r("1"))
    assert.are.equal("1", r("1", true))
    assert.are.equal("é", r("2"))
    assert.are.equal("2", r("2", true))
    assert.are.equal("à", r("0"))
    assert.are.equal("0", r("0", true))
  end)
end)
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: FAIL — the new `describe("keyboard_layout.resolve (fr)", ...)` examples fail (`M.resolve("fr", ...)` returns `nil` because `M.layouts.fr` doesn't exist yet). The pre-existing "us" examples still pass.

- [ ] **Step 3: Add the `fr` layout**

In `overlay/koreader/patches/okaywrite/keyboard_layout.lua`, add a new key to `M.layouts` (a sibling of `us`, inside the same `M.layouts = { ... }` table — add a comma after the `us` table's closing `}` and insert this before the final `}`):

```lua
  fr = {
    -- AZERTY repositions some letters; give them explicit entries (anything
    -- else falls back to identity, same as "us").
    ["Q"] = { base = "a", shift = "A" },
    ["A"] = { base = "q", shift = "Q" },
    ["W"] = { base = "z", shift = "Z" },
    ["Z"] = { base = "w", shift = "W" },
    -- US "M" position produces AZERTY's comma key; the accented letters that
    -- sit under US ;/' on a US board take its place instead.
    ["M"] = { base = ",", shift = "?" },
    [","] = { base = ";", shift = "." },
    ["."] = { base = ":", shift = "/" },
    ["/"] = { base = "!", shift = "§" },
    [";"] = { base = "m", shift = "M" },
    ["'"] = { base = "ù", shift = "%" },
    -- Digit row: AZERTY is unshifted-symbol / shifted-digit, opposite of US.
    ["1"] = { base = "&", shift = "1" },
    ["2"] = { base = "é", shift = "2" },
    ["3"] = { base = '"', shift = "3" },
    ["4"] = { base = "'", shift = "4" },
    ["5"] = { base = "(", shift = "5" },
    ["6"] = { base = "-", shift = "6" },
    ["7"] = { base = "è", shift = "7" },
    ["8"] = { base = "_", shift = "8" },
    ["9"] = { base = "ç", shift = "9" },
    ["0"] = { base = "à", shift = "0" },
    ["-"] = { base = ")", shift = "°" },
    ["="] = { base = "=", shift = "+" },
    ["]"] = { base = "$", shift = "£" },
    ["\\"] = { base = "*", shift = "µ" },
  },
```

- [ ] **Step 4: Run to verify all tests pass**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: PASS (all "us" and "fr" examples).

- [ ] **Step 5: Commit**

```bash
git add overlay/koreader/patches/okaywrite/keyboard_layout.lua spec/keyboard_layout_spec.lua
git commit -m "$(cat <<'EOF'
Add French (AZERTY) physical-keyboard layout

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 3: Add the German (QWERTZ) physical-keyboard layout

**Files:**
- Modify: `overlay/koreader/patches/okaywrite/keyboard_layout.lua`
- Test: `spec/keyboard_layout_spec.lua`

**Interfaces:**
- Consumes: `M.resolve` from Task 1.
- Produces: `M.layouts.de`, consumed later by Task 6.

- [ ] **Step 1: Write the failing tests**

Append to `spec/keyboard_layout_spec.lua`:

```lua
describe("keyboard_layout.resolve (de)", function()
  local function r(name, shift, altgr)
    return M.resolve("de", name, { shift = shift or false, altgr = altgr or false })
  end

  it("swaps Y and Z (QWERTZ)", function()
    assert.are.equal("z", r("Y"))
    assert.are.equal("Z", r("Y", true))
    assert.are.equal("y", r("Z"))
  end)

  it("puts umlauts and ß on their dedicated base-level keys", function()
    assert.are.equal("ä", r("'"))
    assert.are.equal("Ä", r("'", true))
    assert.are.equal("ö", r(";"))
    assert.are.equal("ü", r("["))
    assert.are.equal("ß", r("-"))
  end)

  it("maps the shifted digit row to German symbols", function()
    assert.are.equal("!", r("1", true))
    assert.are.equal('"', r("2", true))
    assert.are.equal("§", r("3", true))
  end)
end)
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: FAIL — the new "de" examples fail; "us" and "fr" examples still pass.

- [ ] **Step 3: Add the `de` layout**

Add to `M.layouts` in `overlay/koreader/patches/okaywrite/keyboard_layout.lua` (sibling of `us`/`fr`):

```lua
  de = {
    ["Y"] = { base = "z", shift = "Z" },
    ["Z"] = { base = "y", shift = "Y" },
    ["'"] = { base = "ä", shift = "Ä" },
    [";"] = { base = "ö", shift = "Ö" },
    ["["] = { base = "ü", shift = "Ü" },
    ["-"] = { base = "ß", shift = "?" },
    ["`"] = { base = "^", shift = "°" },
    ["]"] = { base = "+", shift = "*" },
    ["\\"] = { base = "#", shift = "'" },
    [","] = { base = ",", shift = ";" },
    ["."] = { base = ".", shift = ":" },
    ["/"] = { base = "-", shift = "_" },
    ["1"] = { base = "1", shift = "!" },
    ["2"] = { base = "2", shift = '"' },
    ["3"] = { base = "3", shift = "§" },
    ["4"] = { base = "4", shift = "$" },
    ["5"] = { base = "5", shift = "%" },
    ["6"] = { base = "6", shift = "&" },
    ["7"] = { base = "7", shift = "/" },
    ["8"] = { base = "8", shift = "(" },
    ["9"] = { base = "9", shift = ")" },
    ["0"] = { base = "0", shift = "=" },
  },
```

- [ ] **Step 4: Run to verify all tests pass**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: PASS (all "us", "fr", "de" examples).

- [ ] **Step 5: Commit**

```bash
git add overlay/koreader/patches/okaywrite/keyboard_layout.lua spec/keyboard_layout_spec.lua
git commit -m "$(cat <<'EOF'
Add German (QWERTZ) physical-keyboard layout

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 4: Add the Italian physical-keyboard layout

**Files:**
- Modify: `overlay/koreader/patches/okaywrite/keyboard_layout.lua`
- Test: `spec/keyboard_layout_spec.lua`

**Interfaces:**
- Consumes: `M.resolve` from Task 1.
- Produces: `M.layouts.it`, consumed later by Task 6. (Note: this is the *physical*-keyboard layout key; KOReader's on-screen keyboard has no dedicated Italian layout upstream and already falls back to English — unrelated but worth remembering when reading Task 9's keyboard-layout keep-list.)

- [ ] **Step 1: Write the failing tests**

Append to `spec/keyboard_layout_spec.lua`:

```lua
describe("keyboard_layout.resolve (it)", function()
  local function r(name, shift, altgr)
    return M.resolve("it", name, { shift = shift or false, altgr = altgr or false })
  end

  it("does not reposition any letters", function()
    assert.are.equal("q", r("Q"))
    assert.are.equal("Q", r("Q", true))
  end)

  it("puts accented vowels on their dedicated base-level keys", function()
    assert.are.equal("è", r("["))
    assert.are.equal("é", r("[", true))
    assert.are.equal("ò", r(";"))
    assert.are.equal("à", r("'"))
    assert.are.equal("ì", r("="))
  end)

  it("maps the shifted digit row to Italian symbols", function()
    assert.are.equal("!", r("1", true))
    assert.are.equal("£", r("3", true))
  end)
end)
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: FAIL — the new "it" examples fail; all others still pass.

- [ ] **Step 3: Add the `it` layout**

Add to `M.layouts`:

```lua
  it = {
    ["`"] = { base = "\\", shift = "|" },
    ["-"] = { base = "'", shift = "?" },
    ["="] = { base = "ì", shift = "^" },
    ["["] = { base = "è", shift = "é" },
    ["]"] = { base = "+", shift = "*" },
    [";"] = { base = "ò", shift = "ç" },
    ["'"] = { base = "à", shift = "°" },
    ["\\"] = { base = "ù", shift = "§" },
    [","] = { base = ",", shift = ";" },
    ["."] = { base = ".", shift = ":" },
    ["/"] = { base = "-", shift = "_" },
    ["1"] = { base = "1", shift = "!" },
    ["2"] = { base = "2", shift = '"' },
    ["3"] = { base = "3", shift = "£" },
    ["4"] = { base = "4", shift = "$" },
    ["5"] = { base = "5", shift = "%" },
    ["6"] = { base = "6", shift = "&" },
    ["7"] = { base = "7", shift = "/" },
    ["8"] = { base = "8", shift = "(" },
    ["9"] = { base = "9", shift = ")" },
    ["0"] = { base = "0", shift = "=" },
  },
```

- [ ] **Step 4: Run to verify all tests pass**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: PASS (all examples across "us", "fr", "de", "it").

- [ ] **Step 5: Commit**

```bash
git add overlay/koreader/patches/okaywrite/keyboard_layout.lua spec/keyboard_layout_spec.lua
git commit -m "$(cat <<'EOF'
Add Italian physical-keyboard layout

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 5: Add the Spanish physical-keyboard layout

**Files:**
- Modify: `overlay/koreader/patches/okaywrite/keyboard_layout.lua`
- Test: `spec/keyboard_layout_spec.lua`

**Interfaces:**
- Consumes: `M.resolve` from Task 1.
- Produces: `M.layouts.es`, consumed later by Task 6.

- [ ] **Step 1: Write the failing tests**

Append to `spec/keyboard_layout_spec.lua`:

```lua
describe("keyboard_layout.resolve (es)", function()
  local function r(name, shift, altgr)
    return M.resolve("es", name, { shift = shift or false, altgr = altgr or false })
  end

  it("does not reposition any letters", function()
    assert.are.equal("q", r("Q"))
  end)

  it("puts ñ, ¡, ¿ on their dedicated base-level keys", function()
    assert.are.equal("ñ", r(";"))
    assert.are.equal("Ñ", r(";", true))
    assert.are.equal("¡", r("="))
    assert.are.equal("¿", r("=", true))
  end)

  it("leaves the accent dead keys unmapped (dead keys are out of scope)", function()
    assert.is_nil(r("["))
    assert.is_nil(r("'"))
  end)

  it("maps the shifted digit row to Spanish symbols", function()
    assert.are.equal("!", r("1", true))
    assert.are.equal("·", r("3", true))
  end)
end)
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: FAIL — the new "es" examples fail; all others still pass.

- [ ] **Step 3: Add the `es` layout**

Add to `M.layouts`:

```lua
  es = {
    ["`"] = { base = "º", shift = "ª" },
    ["-"] = { base = "'", shift = "?" },
    ["="] = { base = "¡", shift = "¿" },
    ["]"] = { base = "+", shift = "*" },
    [";"] = { base = "ñ", shift = "Ñ" },
    [","] = { base = ",", shift = ";" },
    ["."] = { base = ".", shift = ":" },
    ["/"] = { base = "-", shift = "_" },
    ["1"] = { base = "1", shift = "!" },
    ["2"] = { base = "2", shift = '"' },
    ["3"] = { base = "3", shift = "·" },
    ["4"] = { base = "4", shift = "$" },
    ["5"] = { base = "5", shift = "%" },
    ["6"] = { base = "6", shift = "&" },
    ["7"] = { base = "7", shift = "/" },
    ["8"] = { base = "8", shift = "(" },
    ["9"] = { base = "9", shift = ")" },
    ["0"] = { base = "0", shift = "=" },
    -- "[" (dead-key ` on real ES hardware) and "'" (dead-key ´) are
    -- deliberately unmapped: accented vowels (á é í ó ú) need a compose
    -- sequence, out of scope per the spec's non-goals. Only ñ/¡/¿ -- all
    -- dedicated keys, not dead keys -- are supported.
  },
```

- [ ] **Step 4: Run to verify all tests pass**

Run: `busted spec/keyboard_layout_spec.lua`
Expected: PASS (all examples across "us", "fr", "de", "it", "es").

- [ ] **Step 5: Commit**

```bash
git add overlay/koreader/patches/okaywrite/keyboard_layout.lua spec/keyboard_layout_spec.lua
git commit -m "$(cat <<'EOF'
Add Spanish physical-keyboard layout

Accented vowels are out of scope: real Spanish hardware types them
via a dead-key compose sequence, which this project doesn't support.
ñ/¡/¿ are dedicated (non-dead) keys and are supported.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 6: Make the physical-keyboard layout follow the UI language

**Files:**
- Modify: `overlay/koreader/patches/2-okaywrite-keyboard.lua`

**Interfaces:**
- Consumes: `M.layouts.{us,fr,de,it,es}` from Tasks 1-5; `G_reader_settings:readSetting("language")` (KOReader core, returns `"C"`, `"en_GB"`, `"de"`, `"es"`, `"fr"`, or `"it_IT"` given Task 8's restricted language menu).
- Produces: `getActiveLayout()` (local function, no external consumers outside this file).

Today `ACTIVE_LAYOUT` is hardcoded to `"us"`. This task makes it follow whichever UI language the user has selected, with no new settings UI.

This file has no automated tests (it wraps live KOReader classes — `InputText`, `Device` — which aren't available outside a running KOReader; the existing physical-keyboard feature has the same property). Verify manually per Step 3.

- [ ] **Step 1: Replace the hardcoded `ACTIVE_LAYOUT` constant**

In `overlay/koreader/patches/2-okaywrite-keyboard.lua`:

Old:
```lua
local layout = dofile(DataStorage:getPatchesDir() .. "/okaywrite/keyboard_layout.lua")
local ACTIVE_LAYOUT = "us"
```
New:
```lua
local layout = dofile(DataStorage:getPatchesDir() .. "/okaywrite/keyboard_layout.lua")

-- Physical layout follows the UI language setting; anything without a
-- dedicated M.layouts entry falls back to "us". "C" is KOReader's
-- untranslated-source-strings locale (English) -- there is no separate "en"
-- locale upstream.
local LANGUAGE_TO_KEYBOARD_LAYOUT = {
    C = "us",
    en_GB = "us",
    de = "de",
    es = "es",
    fr = "fr",
    it_IT = "it",
}
local function getActiveLayout()
    local lang = G_reader_settings:readSetting("language") or "C"
    return LANGUAGE_TO_KEYBOARD_LAYOUT[lang] or "us"
end
```

- [ ] **Step 2: Update the resolve call site**

Old:
```lua
            local ch = layout.resolve(ACTIVE_LAYOUT, key.key, { shift = shift, altgr = altgr })
```
New:
```lua
            local ch = layout.resolve(getActiveLayout(), key.key, { shift = shift, altgr = altgr })
```

- [ ] **Step 3: Manual verification (fast-iteration loop)**

Copy `overlay/koreader/patches/2-okaywrite-keyboard.lua` and `overlay/koreader/patches/okaywrite/keyboard_layout.lua` into a running KOReader install's `koreader/patches/` (see README's "Fast iteration loop"). Relaunch.

- Settings → Language → German. In the text editor, type on a paired BT keyboard: pressing the key at the US "Y" position produces "z" (QWERTZ swap); the key at the US "'" position produces "ä".
- Settings → Language → French. The key at the US "Q" position produces "a"; the key at the US "1" position produces "&", and with Shift produces "1".
- Settings → Language → English ("C"). Physical keyboard behaves exactly as before this task (US layout).

- [ ] **Step 4: Commit**

```bash
git add overlay/koreader/patches/2-okaywrite-keyboard.lua
git commit -m "$(cat <<'EOF'
Follow the UI language for the physical-keyboard layout

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 7: Fix Alt/Meta modifier tracking; add terminal-style word/line cursor movement

**Files:**
- Modify: `overlay/koreader/patches/2-okaywrite-keyboard.lua`

**Interfaces:**
- Consumes: `Device.input.event_map` (KOReader core, mutated on `PhysicalKeyboardConnected` by the existing `setupKeyboard` wrap); `InputText:getStringPos(is_word, left_to_cursor)`, `InputText:moveCursorToCharPos(char_pos)`, `InputText:goToStartOfLine()`, `InputText:goToEndOfLine()` — all pre-existing KOReader `InputText` methods (confirmed present at `v2026.07.1`, `frontend/ui/widget/inputtext.lua`), not modified by this task.
- Produces: nothing new consumed elsewhere; this is the terminal-movement feature itself.

**Why this is needed:** KOReader's Kindle external-keyboard event map (`event_map_keyboard.lua`) reports `"LAlt"`/`"RAlt"`/`"LMeta"`/`"RMeta"`, but `Device.input.modifiers` (`frontend/device/input.lua`) only tracks the literal names `"Alt"`/`"Ctrl"`/`"Shift"`/`"Sym"`/`"Meta"`/`"ScreenKB"` as held state. None of the reported names match `"Alt"` or `"Meta"` exactly, so — independent of the already-documented AltGr gap — plain Alt and Meta/Cmd are *also* never tracked as held on a physical keyboard today. This task extends the existing `EVENT_MAP_FIXES` mechanism (already used to fix punctuation-key names) to rename Left-Alt and both Meta keys to the names the modifier tracker recognizes, leaving Right-Alt (`"RAlt"`, reserved for AltGr) untouched.

- [ ] **Step 1: Extend `EVENT_MAP_FIXES` and its doc comment**

Old:
```lua
-- 1) Normalize the external-keyboard event map so punctuation keys have correct
--    names. Applied by wrapping the plugin's setupKeyboard (runs on connect).
--
-- Confirmed missing/wrong at tag v2026.07.1 in event_map_keyboard.lua:
--   [12] absent  → "-"     KEY_MINUS
--   [13] absent  → "="     KEY_EQUAL
--   [26] absent  → "["     KEY_LEFTBRACE
--   [27] absent  → "]"     KEY_RIGHTBRACE
--   [39] = ":"   → ";"     KEY_SEMICOLON  (wrong: should be base char)
--   [41] absent  → "`"     KEY_GRAVE
-- Already correct: [40]="'", [43]="\\", [51]=",", [52]=".", [53]="/"
local EVENT_MAP_FIXES = {
    [12] = "-",
    [13] = "=",
    [26] = "[",
    [27] = "]",
    [39] = ";",
    [41] = "`",
}
```
New:
```lua
-- 1) Normalize the external-keyboard event map so punctuation keys have correct
--    names, and so Alt/Meta are tracked as held modifiers at all. Applied by
--    wrapping the plugin's setupKeyboard (runs on connect).
--
-- Confirmed missing/wrong at tag v2026.07.1 in event_map_keyboard.lua:
--   [12] absent  → "-"     KEY_MINUS
--   [13] absent  → "="     KEY_EQUAL
--   [26] absent  → "["     KEY_LEFTBRACE
--   [27] absent  → "]"     KEY_RIGHTBRACE
--   [39] = ":"   → ";"     KEY_SEMICOLON  (wrong: should be base char)
--   [41] absent  → "`"     KEY_GRAVE
-- Already correct: [40]="'", [43]="\\", [51]=",", [52]=".", [53]="/"
--
-- Device.input.modifiers (frontend/device/input.lua) only tracks the exact
-- names "Alt"/"Ctrl"/"Shift"/"Sym"/"Meta"/"ScreenKB" as held state, but this
-- event map reports "LAlt"/"RAlt"/"LCtrl"/"LMeta"/"RMeta" -- none of which
-- match "Alt"/"Meta" literally, so those two are never tracked as held
-- through this map. Renaming Left-Alt and both Meta keys to the generic
-- names fixes that; Right-Alt stays "RAlt" (reserved for AltGr, see above).
local EVENT_MAP_FIXES = {
    [12] = "-",
    [13] = "=",
    [26] = "[",
    [27] = "]",
    [39] = ";",
    [41] = "`",
    [56] = "Alt",   -- KEY_LEFTALT (was "LAlt")
    [125] = "Meta", -- KEY_LEFTMETA (was "LMeta")
    [126] = "Meta", -- KEY_RIGHTMETA (was "RMeta")
}
```

- [ ] **Step 2: Add the word/line-movement branch to the `onKeyPress` wrapper**

Old:
```lua
local orig_onKeyPress = InputText.onKeyPress
InputText.onKeyPress = function(self, key)
    if not Device:isSDL() and type(key.key) == "string" then
        -- Only intercept when modifiers are a subset of { Shift, AltGr }.
        local shift = key["Shift"] and true or false
        local altgr = false
        for _, n in ipairs(ALTGR_KEYS) do
            if key[n] then altgr = true end
        end

        local other_modifier = false
        for name, flag in pairs(key.modifiers or {}) do
            if flag and name ~= "Shift" then
                local is_altgr = false
                for _, n in ipairs(ALTGR_KEYS) do
                    if name == n then is_altgr = true end
                end
                if not is_altgr then other_modifier = true end
            end
        end

        if not other_modifier then
            local ch = layout.resolve(getActiveLayout(), key.key, { shift = shift, altgr = altgr })
            if ch then
                self:addChars(ch)
                return true
            end
        end
    end
    return orig_onKeyPress(self, key)
end
```
New:
```lua
local orig_onKeyPress = InputText.onKeyPress
InputText.onKeyPress = function(self, key)
    if not Device:isSDL() and type(key.key) == "string" then
        if key.key == "Left" or key.key == "Right" then
            -- Terminal-style word/line movement. Plain and otherwise-modified
            -- Left/Right fall through to the original (arrow move, etc.).
            local mods = key.modifiers or {}
            if mods["Alt"] and not mods["Meta"] then
                if key.key == "Left" then
                    self:moveCursorToCharPos(self:getStringPos(true, true))
                else
                    local _, end_pos = self:getStringPos(true, false)
                    self:moveCursorToCharPos(end_pos + 1)
                end
                return true
            elseif mods["Meta"] and not mods["Alt"] then
                if key.key == "Left" then
                    self:goToStartOfLine()
                else
                    self:goToEndOfLine()
                end
                return true
            end
        else
            -- Only intercept when modifiers are a subset of { Shift, AltGr }.
            local shift = key["Shift"] and true or false
            local altgr = false
            for _, n in ipairs(ALTGR_KEYS) do
                if key[n] then altgr = true end
            end

            local other_modifier = false
            for name, flag in pairs(key.modifiers or {}) do
                if flag and name ~= "Shift" then
                    local is_altgr = false
                    for _, n in ipairs(ALTGR_KEYS) do
                        if name == n then is_altgr = true end
                    end
                    if not is_altgr then other_modifier = true end
                end
            end

            if not other_modifier then
                local ch = layout.resolve(getActiveLayout(), key.key, { shift = shift, altgr = altgr })
                if ch then
                    self:addChars(ch)
                    return true
                end
            end
        end
    end
    return orig_onKeyPress(self, key)
end
```

- [ ] **Step 3: Manual verification (fast-iteration loop)**

Copy the updated `2-okaywrite-keyboard.lua` into a running install's `koreader/patches/`, relaunch. In the text editor, with a BT keyboard paired, type a few words and:

- Alt+Left from the end of the text moves the cursor to the start of the last word, not one character left. Repeating moves to the start of the previous word.
- Alt+Right from mid-word moves to just past the end of the current/next word.
- Cmd+Left moves the cursor to the start of the current line (not the start of the whole document). Cmd+Right moves to the end of the current line.
- Plain Left/Right, Backspace, Home/End, and Ctrl-combos all still behave exactly as before (delegated to the original, untouched by this task).
- Alt+F4 now closes the app (a side effect of Alt finally being tracked correctly) — confirm this doesn't surprise anyone; it's the existing stock KOReader shortcut, not new behavior we added.

- [ ] **Step 4: Commit**

```bash
git add overlay/koreader/patches/2-okaywrite-keyboard.lua
git commit -m "$(cat <<'EOF'
Add terminal-style Alt/Cmd+arrow word/line cursor movement

Fixes Alt/Meta modifier tracking on the Kindle external-keyboard event
map (it reports LAlt/RAlt/LMeta/RMeta; Device.input.modifiers only
recognizes literal Alt/Meta), then wires Alt+Left/Right to word jump
and Cmd+Left/Right to line start/end using InputText's existing
getStringPos/moveCursorToCharPos/goToStartOfLine/goToEndOfLine.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 8: Restrict the language and keyboard-layout menus to EFIGS; remove Cloud storage

**Files:**
- Create: `overlay/koreader/patches/2-okaywrite-menus.lua`

**Interfaces:**
- Consumes: `Language:genLanguageSubItem(lang_locale)` (KOReader core method, pre-existing, `frontend/ui/language.lua`); `VirtualKeyboard.lang_to_keyboard_layout` / `VirtualKeyboard.lang_has_submenu` (KOReader core class tables, `frontend/ui/widget/virtualkeyboard.lua`); `FileManagerMenu:setUpdateItemTable` (KOReader core method, `frontend/apps/filemanager/filemanagermenu.lua`).
- Produces: nothing consumed elsewhere; this is a self-contained menu-restriction patch.

Both the language menu and the on-screen-keyboard-layout menu are hardcoded Lua tables in KOReader, not directory scans — confirmed by reading `frontend/ui/language.lua` (`Language:getLangMenuTable()` builds `sub_item_table` from an explicit list of `genLanguageSubItem` calls) and `frontend/ui/widget/virtualkeyboard.lua` (`lang_to_keyboard_layout` is a plain table iterated by the layout submenu). Restricting them to EFIGS means editing these, not deleting files (Task 9 handles the actual deletable data). The file manager's "Cloud storage" menu entry (`frontend/apps/filemanager/filemanagermenu.lua`, `self.menu_items.cloud_storage`) is removed the same way the existing patches remove/add menu entries: wrap the builder function and delete the key afterward.

No automated tests (wraps live KOReader classes not available outside a running install). Verify manually per Step 2.

- [ ] **Step 1: Create the patch file**

Create `overlay/koreader/patches/2-okaywrite-menus.lua`:

```lua
-- OkayWrite: restrict the language and on-screen-keyboard-layout menus to
-- EFIGS (English, French, Italian, German, Spanish), and remove the file
-- manager's "Cloud storage" menu entry. Task 9's build-time prune deletes the
-- underlying files these menus would otherwise offer; this patch is what
-- actually keeps them from being selectable/reachable in the running app,
-- since both menus are hardcoded Lua tables, not directory scans.

local _ = require("gettext")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local Language = require("ui/language")
local VirtualKeyboard = require("ui/widget/virtualkeyboard")

-- 1) Language menu: only the five supported UI languages. "C" is KOReader's
--    untranslated-source-strings locale (English); there is no separate "en".
local EFIGS_LANGUAGES = { "C", "de", "es", "fr", "it_IT" }
Language.getLangMenuTable = function(self)
    if not self.LangMenuTable then
        local sub_item_table = {}
        for _, lang in ipairs(EFIGS_LANGUAGES) do
            table.insert(sub_item_table, self:genLanguageSubItem(lang))
        end
        self.LangMenuTable = {
            text = _("Language"),
            sub_item_table = sub_item_table,
        }
    end
    return self.LangMenuTable
end

-- 2) On-screen-keyboard layout menu: only the EFIGS layouts that exist
--    upstream (Italian has none and already falls back to English -- see
--    VirtualKeyboard:init()'s "lang_to_keyboard_layout[lang] or ...['en']").
--    Mutating the shared table means the existing submenu-generation code
--    (frontend/ui/elements/menu_keyboard_layout.lua) needs no changes.
local EFIGS_KEYBOARD_LANGS = { en = true, es = true, fr = true, de = true }
for lang in pairs(VirtualKeyboard.lang_to_keyboard_layout) do
    if not EFIGS_KEYBOARD_LANGS[lang] then
        VirtualKeyboard.lang_to_keyboard_layout[lang] = nil
    end
end
for lang in pairs(VirtualKeyboard.lang_has_submenu) do
    if not EFIGS_KEYBOARD_LANGS[lang] then
        VirtualKeyboard.lang_has_submenu[lang] = nil
    end
end

-- 3) Remove the file manager's "Cloud storage" menu entry.
local orig_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
FileManagerMenu.setUpdateItemTable = function(self, ...)
    orig_setUpdateItemTable(self, ...)
    self.menu_items.cloud_storage = nil
end
```

- [ ] **Step 2: Manual verification (fast-iteration loop)**

Copy `2-okaywrite-menus.lua` into a running install's `koreader/patches/`, relaunch.

- Settings → Language: exactly five entries (English, Français, Italiano, Deutsch, Español), none of the ~55 others.
- Settings → Keyboard → Keyboard layouts: exactly four entries (English, Spanish, French, German) — no Italian entry (matches the upstream fallback-to-English behavior, unchanged by this patch).
- File manager main menu: no "Cloud storage" entry anywhere.
- Confirm the patch-management menu reports this patch loaded successfully (no failure `InfoMessage`).

- [ ] **Step 3: Commit**

```bash
git add overlay/koreader/patches/2-okaywrite-menus.lua
git commit -m "$(cat <<'EOF'
Restrict language/keyboard-layout menus to EFIGS; remove Cloud storage

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 9: Prune non-notepad plugins, cloud storage app, and non-EFIGS data at build time

**Files:**
- Create: `overlay/koreader/prune/plugins-delete.txt`
- Create: `overlay/koreader/prune/l10n-keep.txt`
- Create: `overlay/koreader/prune/keyboardlayouts-keep.txt`
- Modify: `build.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing consumed elsewhere; this is the build-time deletion step.

Verified against the real `v2026.07.1` Kindle release tree: plugins are self-contained `.koplugin` directories with no cross-plugin static `require`s of each other's internals, so deleting a plugin directory is safe on its own (unlike `frontend/apps/reader/`, which Task-8-adjacent design work already confirmed is *not* independently deletable — see the spec's Non-goals). `l10n/` language folders and `frontend/ui/data/keyboardlayouts/*.lua` files are plain data, loaded dynamically by language code, not statically required by name — also safe to delete outside the keep list. `frontend/apps/cloudstorage/` is only `require`d lazily (inside callback functions, not at module load time) from `filemanagermenu.lua` and `ui/downloadmgr.lua`, and Task 8 already removes the one reachable menu entry that would trigger it, so deleting it is safe.

- [ ] **Step 1: Create the plugin delete-list**

Create `overlay/koreader/prune/plugins-delete.txt`:
```
SSH.koplugin
archiveviewer.koplugin
autoturn.koplugin
bookshortcuts.koplugin
calibre.koplugin
cloudstorage.koplugin
coverbrowser.koplugin
coverimage.koplugin
docsettingtweak.koplugin
exporter.koplugin
hello.koplugin
hotkeys.koplugin
httpinspector.koplugin
japanese.koplugin
keepalive.koplugin
kosync.koplugin
movetoarchive.koplugin
newsdownloader.koplugin
opds.koplugin
perceptionexpander.koplugin
profiles.koplugin
qrclipboard.koplugin
readtimer.koplugin
statistics.koplugin
terminal.koplugin
vocabbuilder.koplugin
wallabag.koplugin
```

Kept (not listed, so not deleted): `autodim.koplugin`, `autostandby.koplugin`, `autosuspend.koplugin`, `autowarmth.koplugin`, `batterystat.koplugin`, `externalkeyboard.koplugin`, `gestures.koplugin`, `systemstat.koplugin`, `texteditor.koplugin`, `timesync.koplugin` — power/status management and the notepad's own core plugins, none of them reading-specific.

- [ ] **Step 2: Create the l10n keep-list**

Create `overlay/koreader/prune/l10n-keep.txt`:
```
de
es
fr
it_IT
```
(English has no `l10n/` folder — it's KOReader's untranslated source-string locale.)

- [ ] **Step 3: Create the keyboard-layouts keep-list**

Create `overlay/koreader/prune/keyboardlayouts-keep.txt`:
```
en_keyboard.lua
es_keyboard.lua
fr_keyboard.lua
de_keyboard.lua
keypopup/en_popup.lua
```
(Confirmed: no dedicated Italian on-screen-keyboard file exists upstream; `generic_ime.lua` and every other `keypopup/*.lua` are only used by the CJK/other-language layouts being deleted.)

- [ ] **Step 4: Add the prune step to `build.sh`**

In `build.sh`, add a new function (place it above `build_one`, after the `mkdir -p "$CACHE_DIR" "$DIST_DIR"` line):

```bash
prune_release() {
    local work="$1"
    local ko="$work/koreader"

    echo "    pruning to notepad-only"

    # Non-notepad plugins.
    while IFS= read -r plugin; do
        [[ -z "$plugin" || "$plugin" == \#* ]] && continue
        rm -rf "$ko/plugins/$plugin"
    done < "$OVERLAY_DIR/koreader/prune/plugins-delete.txt"

    # Cloud storage app (its one reachable menu entry is removed by
    # 2-okaywrite-menus.lua; this removes the underlying implementation too).
    rm -rf "$ko/frontend/apps/cloudstorage"

    # Non-EFIGS localization data (l10n/LICENSE and l10n/README.md are text
    # files, not language directories, and are left alone by the */ glob).
    for dir in "$ko/l10n"/*/; do
        local lang; lang="$(basename "$dir")"
        if ! grep -qx "$lang" "$OVERLAY_DIR/koreader/prune/l10n-keep.txt"; then
            rm -rf "$dir"
        fi
    done

    # Non-EFIGS on-screen keyboard layouts. generic_ime.lua is only used by
    # the CJK IME layouts already excluded above.
    local kb_dir="$ko/frontend/ui/data/keyboardlayouts"
    rm -f "$kb_dir/generic_ime.lua"
    for f in "$kb_dir"/*.lua; do
        local name; name="$(basename "$f")"
        if ! grep -qx "$name" "$OVERLAY_DIR/koreader/prune/keyboardlayouts-keep.txt"; then
            rm -f "$f"
        fi
    done
    for f in "$kb_dir/keypopup"/*.lua; do
        local name; name="keypopup/$(basename "$f")"
        if ! grep -qx "$name" "$OVERLAY_DIR/koreader/prune/keyboardlayouts-keep.txt"; then
            rm -f "$f"
        fi
    done
}
```

Then call it from `build_one`, right after extraction and before the overlay is applied:

Old:
```bash
    echo "==> [$gen] extracting"
    unzip -q "$cached" -d "$work"

    echo "==> [$gen] applying overlay"
```
New:
```bash
    echo "==> [$gen] extracting"
    unzip -q "$cached" -d "$work"

    prune_release "$work"

    echo "==> [$gen] applying overlay"
```

- [ ] **Step 5: Verify the prune step against a real release**

Run:
```bash
./build.sh kindlepw2
```
Expected: build completes without error, and the resulting `dist/okaywrite-kindlepw2-v2026.07.1.zip` — when inspected (`unzip -l dist/okaywrite-kindlepw2-v2026.07.1.zip | grep -c koplugin`) — contains exactly the 10 kept plugins, no `frontend/apps/cloudstorage/`, `l10n/` containing only `de`, `es`, `fr`, `it_IT` (plus `LICENSE`/`README.md`), and `frontend/ui/data/keyboardlayouts/` containing only the 4 kept `*_keyboard.lua` files plus `keypopup/en_popup.lua`.

- [ ] **Step 6: Manual verification on a live install (fast-iteration loop)**

This is the empirical check the design calls for before trusting the prune list: unzip the freshly built package (or copy just the pruned `plugins/`, `l10n/`, and `frontend/` trees) over a running install, or install the built package fresh, and confirm:

- App boots straight to the file manager (unchanged from today).
- File manager loads with no crash / no "plugin failed to load" `InfoMessage` (this is the check that catches an accidentally-deleted plugin some other kept code still depends on).
- New file / Save as (existing features) still work.
- Opening a `.txt` file in the text editor still works, including all keyboard behavior from Tasks 2-8.
- No PDF/EPUB/reader entry point is reachable through normal use (unchanged from today — the reader code is still present per the spec's Non-goals, just as unreachable as before).

If any step here reveals a missing dependency, remove the offending name from `plugins-delete.txt` (or the relevant keep-list) and re-run from Step 5 — this file is the actual source of truth for what's safe to prune, refined empirically, exactly as the spec describes.

- [ ] **Step 7: Commit**

```bash
git add overlay/koreader/prune/ build.sh
git commit -m "$(cat <<'EOF'
Prune non-notepad plugins and non-EFIGS data at build time

Deletes plugins outside the notepad's needs, the cloud storage app
(its menu entry is removed separately), non-EFIGS l10n/ folders, and
non-EFIGS on-screen-keyboard-layout files, from the downloaded release
before the overlay is applied. frontend/apps/reader/ is intentionally
left untouched -- filemanager.lua has hard load-time dependencies on
several of its modules (dictionary/Wikipedia/device-status lookups),
confirmed by reading the pinned v2026.07.1 source tree.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```

---

## Task 10: Update README to describe the trimmed app accurately

**Files:**
- Modify: `README.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Update the roadmap and "What it does" sections**

In `README.md`, update the "What it does (today)" list and the roadmap table to describe this branch's actual, verified state rather than the old overlay-only description:

- Add a bullet under "What it does": "Ships only the plugins and languages a notepad needs — dictionary/OPDS/cloud-sync/statistics/etc. plugins, and every UI language outside English/French/Italian/German/Spanish, are deleted at build time, not just hidden."
- Add a bullet: "Physical (Bluetooth) keyboard support covers English/French/Italian/German/Spanish layouts, including terminal-style Alt+Left/Right (word jump) and Cmd+Left/Right (line start/end)."
- Add a bullet noting the honest limitation: "The reader engine and PDF/EPUB code are still present in the shipped binary — KOReader's file manager has real code dependencies on parts of the reader app (dictionary/Wikipedia lookups), so it can't be cleanly deleted. It's unreachable through normal use, same as before, just not physically removed."
- Update the Bluetooth keyboard roadmap row's "Notes" column to mention the five supported layouts instead of just "US layout".
- Add a note that Spanish accented vowels (á é í ó ú) aren't supported via physical keyboard (dead-key limitation) but are typeable via the on-screen keyboard.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
Document the trimmed notepad-only app in README

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0167Q7W3Z43inL3AbUseiZNG
EOF
)"
```
