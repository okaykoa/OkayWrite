-- OkayWrite: correct physical-keyboard text input. Resolves (key, modifiers)
-- to a character via a real layout table and inserts finished text, instead of
-- the widget guessing glyphs from key names. Delegates everything else to the
-- original InputText:onKeyPress.

local InputText = require("ui/widget/inputtext")
local Device = require("device")
local DataStorage = require("datastorage")
local userpatch = require("userpatch")

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

-- Right-Alt modifier name confirmed via event_map_keyboard.lua: [100] = "RAlt".
-- Note: Input.modifiers does not include RAlt by default, so AltGr state is
-- not tracked across keypresses; altgr will always be false in practice on
-- current KOReader. Wired correctly per source findings for future-proofing.
local ALTGR_KEYS = { "RAlt" }

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
