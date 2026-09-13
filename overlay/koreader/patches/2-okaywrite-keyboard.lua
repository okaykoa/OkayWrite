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

-- Must match InputText:getStringPos's own `is_word` delimiter pattern exactly
-- (frontend/ui/widget/inputtext.lua) -- duplicated here because getStringPos
-- doesn't expose it as a parameter. If that pattern ever changes upstream,
-- update this too.
local WORD_DELIMITER = "[\n\r%s.,;:!?–—―]"

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
                local ch = layout.resolve(ACTIVE_LAYOUT, key.key, { shift = shift, altgr = altgr })
                if ch then
                    self:addChars(ch)
                    return true
                end
            end
        end
    end
    return orig_onKeyPress(self, key)
end
