--[[
OkayWrite  --  turns a stock KOReader install into a focused writing app.

Userpatch, priority: late (filename prefix "2-").

It only adjusts settings that KOReader already honors -- no core files are
modified, so upgrading KOReader is just a matter of rebuilding:

  * .txt / .md files open in the built-in Text editor on a single tap
    (KOReader's FileManager:openFile calls DocumentRegistry:getProvider with
    include_aux=true, so an associated aux provider like "texteditor" is used).
  * The FileManager opens in a dedicated OkayWrite folder.
  * The app boots straight into the FileManager (never the reader).

Priority "late" means this runs at reader.lua:190, AFTER G_reader_settings has
been loaded (opened at reader.lua:39, well after the "early" patch hooks), which
is exactly what we need to read/write settings. See frontend/userpatch.lua.

This file is intentionally dependency-light and idempotent: it is safe to run
on every startup.
--]]

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- Where documents live. On Kindle the user-visible storage is /mnt/us.
-- Falls back gracefully if the parent does not exist (e.g. desktop testing).
local WRITING_DIR = "/mnt/us/OkayWrite"

-- File types that should open in the Text editor instead of the reader.
local WRITING_EXTENSIONS = { "txt", "md" }

-- If true, always steer .txt/.md to the editor (a dedicated writing device).
-- If false, only set the association when the user has no preference yet.
local FORCE_WRITING_PROVIDER = true

-- ---------------------------------------------------------------------------

-- G_reader_settings must exist by the time a "late" patch runs. Guard anyway
-- so a mis-prioritised copy of this file can never crash startup.
if not G_reader_settings then
    logger.warn("[OkayWrite] G_reader_settings not ready; skipping reskin")
    return
end

-- 1. Make .txt / .md open in the Text editor -------------------------------
-- Stored as G_reader_settings.provider = { <ext> = <provider_key>, ... }.
-- The Text editor plugin registers itself with provider key "texteditor"
-- (plugins/texteditor.koplugin/main.lua: name = "texteditor").
local provider = G_reader_settings:readSetting("provider", {})
for _, ext in ipairs(WRITING_EXTENSIONS) do
    if FORCE_WRITING_PROVIDER or provider[ext] == nil then
        provider[ext] = "texteditor"
    end
end
G_reader_settings:saveSetting("provider", provider)

-- 2. Point the FileManager at the OkayWrite folder -------------------------
-- Create it if we can; only set home_dir if the folder is usable so we never
-- strand the browser on a non-existent path.
if lfs.attributes(WRITING_DIR, "mode") ~= "directory" then
    lfs.mkdir(WRITING_DIR) -- best effort; ignored if parent is missing
end
if lfs.attributes(WRITING_DIR, "mode") == "directory" then
    G_reader_settings:saveSetting("home_dir", WRITING_DIR)
    -- Open here on startup rather than the last-read location.
    G_reader_settings:saveSetting("lastdir", WRITING_DIR)
else
    logger.warn("[OkayWrite] writing dir unavailable, leaving home_dir as-is:", WRITING_DIR)
end

-- 3. Always boot into the FileManager, never the reader ---------------------
G_reader_settings:saveSetting("start_with", "filemanager")

logger.info("[OkayWrite] reskin applied (home_dir=" ..
    tostring(G_reader_settings:readSetting("home_dir")) .. ")")
