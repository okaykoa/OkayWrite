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
