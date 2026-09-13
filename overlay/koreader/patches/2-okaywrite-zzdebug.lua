-- TEMPORARY DIAGNOSTIC PATCH -- delete this file once the double-keystroke
-- investigation is done. Logs every InputText:addChars call to
-- /mnt/us/okaywrite-keydebug.log WITH A FULL LUA STACK TRACE, so we can see
-- exactly which code path is calling it each time -- source-reading alone
-- hasn't found the second caller, so this proves it directly.

local InputText = require("ui/widget/inputtext")
local time = require("ui/time")

local LOG_PATH = "/mnt/us/okaywrite-keydebug.log"
local last_time = nil
local call_count = 0

local orig_addChars = InputText.addChars
InputText.addChars = function(self, chars)
    call_count = call_count + 1
    local f = io.open(LOG_PATH, "a")
    if f then
        local now = time.now()
        local gap_ms = last_time and time.to_ms(now - last_time) or -1
        last_time = now
        f:write(string.format(
            "\n===== addChars call #%d, gap_ms=%d, chars=%s, charpos=%s, #charlist=%s =====\n%s\n",
            call_count, gap_ms, tostring(chars), tostring(self.charpos), tostring(#self.charlist),
            debug.traceback("", 2)))
        f:close()
    end
    return orig_addChars(self, chars)
end
