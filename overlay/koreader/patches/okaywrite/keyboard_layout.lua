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
