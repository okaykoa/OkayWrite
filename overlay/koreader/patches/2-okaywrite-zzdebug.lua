-- TEMPORARY DIAGNOSTIC PATCH -- delete this file once the double-keystroke
-- investigation is done. Logs every InputText key-press event to a plain
-- file on the Kindle's own storage (readable over USB, no terminal needed)
-- so we can see exactly how many onKeyPress calls one physical keystroke
-- produces, and the precise gap between them, independent of KOReader's own
-- logger configuration/level.
--
-- Filename sorts after "2-okaywrite-keyboard.lua" so this wraps OUTSIDE that
-- patch's own onKeyPress wrapper (including its debounce), observing every
-- call exactly as KOReader's UI dispatch makes it.

local InputText = require("ui/widget/inputtext")
local time = require("ui/time")

local LOG_PATH = "/mnt/us/okaywrite-keydebug.log"
local last_time = nil

local orig_onKeyPress = InputText.onKeyPress
InputText.onKeyPress = function(self, key)
    local f = io.open(LOG_PATH, "a")
    if f then
        local mods = {}
        for name, flag in pairs(key.modifiers or {}) do
            if flag then table.insert(mods, name) end
        end
        local now = time.now()
        local gap_ms = last_time and time.to_ms(now - last_time) or -1
        last_time = now
        f:write(string.format("gap_ms=%d key=%s mods=%s\n",
            gap_ms, tostring(key.key), table.concat(mods, ",")))
        f:close()
    end
    return orig_onKeyPress(self, key)
end
