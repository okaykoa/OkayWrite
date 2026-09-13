-- TEMPORARY DIAGNOSTIC PATCH -- delete this file once the double-keystroke
-- investigation is done. Logs every InputText:onKeyPress call AND every
-- InputText:addChars call to /mnt/us/okaywrite-keydebug.log, so we can see
-- exactly how many times each fires per physical keystroke, and in what
-- order -- independent of KOReader's own logger configuration/level.
--
-- Filename sorts after "2-okaywrite-keyboard.lua" so the onKeyPress wrapper
-- here wraps OUTSIDE that patch's own wrapper (including its debounce),
-- observing every call exactly as KOReader's UI dispatch makes it. The
-- addChars wrapper wraps whatever addChars currently is at load time (stock,
-- since no other patch touches it) and stays the innermost/only wrapper.

local InputText = require("ui/widget/inputtext")
local time = require("ui/time")

local LOG_PATH = "/mnt/us/okaywrite-keydebug.log"
local last_time = nil

local function logLine(tag, extra)
    local f = io.open(LOG_PATH, "a")
    if f then
        local now = time.now()
        local gap_ms = last_time and time.to_ms(now - last_time) or -1
        last_time = now
        f:write(string.format("[%s] gap_ms=%d %s\n", tag, gap_ms, extra or ""))
        f:close()
    end
end

local orig_onKeyPress = InputText.onKeyPress
InputText.onKeyPress = function(self, key)
    local mods = {}
    for name, flag in pairs(key.modifiers or {}) do
        if flag then table.insert(mods, name) end
    end
    logLine("onKeyPress", string.format("key=%s mods=%s charpos=%s #charlist=%s",
        tostring(key.key), table.concat(mods, ","), tostring(self.charpos), tostring(#self.charlist)))
    return orig_onKeyPress(self, key)
end

local orig_addChars = InputText.addChars
InputText.addChars = function(self, chars)
    logLine("addChars", string.format("chars=%s charpos=%s #charlist=%s",
        tostring(chars), tostring(self.charpos), tostring(#self.charlist)))
    return orig_addChars(self, chars)
end
