-- OkayWrite: correct physical-keyboard text input. Resolves (key, modifiers)
-- to a character via a real layout table and inserts finished text, instead of
-- the widget guessing glyphs from key names. Delegates everything else to the
-- original InputText:onKeyPress.

local InputText = require("ui/widget/inputtext")
local Device = require("device")
local DataStorage = require("datastorage")
local userpatch = require("userpatch")

local layout = dofile(DataStorage:getPatchesDir() .. "/okaywrite/keyboard_layout.lua")

-- Must match InputText:getStringPos's own `is_word` delimiter pattern exactly
-- (frontend/ui/widget/inputtext.lua) -- duplicated here because getStringPos
-- doesn't expose it as a parameter. If that pattern ever changes upstream,
-- update this too.
local WORD_DELIMITER = "[\n\r%s.,;:!?–—―]"

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

-- Right-Alt modifier name confirmed via event_map_keyboard.lua: [100] = "RAlt".
-- Note: Input.modifiers does not include RAlt by default, so AltGr state is
-- not tracked across keypresses; altgr will always be false in practice on
-- current KOReader. Wired correctly per source findings for future-proofing.
local ALTGR_KEYS = { "RAlt" }

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

-- "externalkeyboard" is the directory-derived plugin name PluginLoader uses
-- (the `name` field inside the plugin's main.lua is overwritten by the loader),
-- so this string is correct and must not be "corrected" to match main.lua.
--
-- Some BT-keyboard passthrough setups (e.g. kindle-hid-passthrough) expose a
-- single physical keyboard as more than one HID interface/event node. The
-- plugin's own findAndSetupKeyboards() deliberately opens an event reader for
-- every node it finds -- per its own comment, "only one would emit the
-- events... the solution is to open all of them", since it can't otherwise
-- tell in advance which one is live. When more than one node for the SAME
-- keyboard actually does emit events, every keystroke is delivered twice
-- (doubled characters, and Left/Right+modifier navigation firing/canceling
-- unpredictably). Dedupe by device name: skip opening a second reader for a
-- name we've already successfully configured.
--
-- This only covers the startup/already-connected enumeration path
-- (setupKeyboard called with a table argument, via findAndSetupKeyboards).
-- The hotplug path (onEvdevInputInsert -> setupKeyboard(event_path), a bare
-- string) resolves the device name internally via a local, unexported
-- function, so it isn't visible here to dedupe against before the fd opens.
local configured_keyboard_names = {}
userpatch.registerPatchPluginFunc("externalkeyboard", function(plugin)
    local orig_setup = plugin.setupKeyboard
    plugin.setupKeyboard = function(self, data, ...)
        if type(data) == "table" and data.name and configured_keyboard_names[data.name] then
            return
        end
        local ret = orig_setup(self, data, ...)
        if type(data) == "table" and data.name and self.keyboard_fds[data.event_path] then
            configured_keyboard_names[data.name] = true
        end
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
        if key.key == "Left" or key.key == "Right" then
            -- Terminal-style word/line movement. Plain and otherwise-modified
            -- Left/Right fall through to the original (arrow move, etc.).
            local mods = key.modifiers or {}
            if mods["Alt"] and not mods["Meta"] then
                -- getStringPos scans outward from the live charpos for the
                -- delimiter above, but doesn't skip past a delimiter char
                -- the cursor is already sitting on. Without this, landing
                -- exactly on a word boundary (which moveCursorToCharPos
                -- below always does) makes the next press's scan match that
                -- same adjacent delimiter immediately and return the same
                -- position again -- deadlocking on the first boundary.
                if key.key == "Left" then
                    while self.charpos > 1 and self.charlist[self.charpos - 1]:find(WORD_DELIMITER) do
                        self.charpos = self.charpos - 1
                    end
                    self:moveCursorToCharPos(self:getStringPos(true, true))
                else
                    while self.charpos <= #self.charlist and self.charlist[self.charpos]:find(WORD_DELIMITER) do
                        self.charpos = self.charpos + 1
                    end
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
        elseif key.key == "Backspace" or key.key == "Del" then
            -- Mirrors the Left/Right convention above: Alt = word-level,
            -- Meta = line-level. There's no established Mac convention for
            -- Meta+Del (delete to end of line), so it's left unbound here --
            -- Meta+Del falls through to the original (plain forward-delete).
            local mods = key.modifiers or {}
            if mods["Alt"] and not mods["Meta"] then
                self:delWord(key.key == "Backspace")
                return true
            elseif mods["Meta"] and not mods["Alt"] and key.key == "Backspace" then
                self:delToStartOfLine()
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
