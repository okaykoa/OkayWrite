-- OkayWrite physical-keyboard layout resolver (dependency-free, unit-testable).
-- Maps (key name, modifier level) -> produced character. A layout entry for a
-- key name always wins, whether that key is a letter or not; a bare A-Z key
-- with no entry falls back to case-folded identity.

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
