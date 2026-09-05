-- OkayWrite: add "Save as" to the Text editor's top-left (☰) menu.
--
-- Reproduces the exact showMenu body from KOReader v2026.07.1
-- (plugins/texteditor.koplugin/main.lua L684-709), adds one extra button row
-- before UIManager:show(dialog), and wires it to the saveAs() helper below.
-- Mirrors the plugin's own newFile() pattern (L339-387) for the filename prompt.

local userpatch = require("userpatch")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local _ = require("gettext")

userpatch.registerPatchPluginFunc("texteditor", function(plugin)
    -- Prompt for a destination path, write the current buffer there, and
    -- continue editing the new file.  Mirrors the plugin's newFile() pattern.
    -- Also called recursively after a PathChooser pick, with new_prefix set.
    plugin.saveAs_helper = function(self, new_prefix)
        local content = self.input:getInputText()
        local file_input
        file_input = InputDialog:new{
            title = _("Save as"),
            input = new_prefix or (self.last_path == "/" and "/" or self.last_path .. "/"),
            buttons = {
                {
                    {
                        text = _("Choose folder"),
                        callback = function()
                            UIManager:close(file_input)
                            local path_chooser = PathChooser:new{
                                select_file = false,
                                path = (new_prefix or (self.last_path == "/" and "/" or self.last_path .. "/")):match("(.*)/"),
                                onConfirm = function(dir_path)
                                    self:saveAs_helper(dir_path .. "/")
                                end,
                            }
                            UIManager:show(path_chooser)
                        end,
                    },
                },
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(file_input)
                        end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local new_path = file_input:getInputText()
                            UIManager:close(file_input)
                            if new_path and new_path ~= "" then
                                self:saveFileContent(new_path, content)
                                self:checkEditFile(new_path, false, true)
                            end
                        end,
                    },
                },
            },
        }
        UIManager:show(file_input)
        file_input:onShowKeyboard()
    end

    -- Reproduce the verbatim showMenu body from v2026.07.1 L684-709, with
    -- one extra button row for "Save as" inserted before UIManager:show(dialog).
    plugin.showMenu = function(self)
        local dialog
        local buttons = {}
        local optionsutil = require("ui/data/optionsutil")
        for i, mode in ipairs(optionsutil.rotation_modes) do
            buttons[i] = {{
                text = optionsutil.rotation_labels[i],
                enabled_func = function()
                    return optionsutil.rotation_modes[i] ~= Screen:getRotationMode()
                end,
                callback = function()
                    UIManager:close(dialog)
                    self.input:onSetRotationMode(optionsutil.rotation_modes[i])
                end,
            }}
        end
        -- OkayWrite addition: "Save as" entry
        table.insert(buttons, { {
            text = _("Save as"),
            callback = function()
                UIManager:close(dialog)
                self:saveAs_helper()
            end,
        } })
        dialog = ButtonDialog:new{
            shrink_unneeded_width = true,
            buttons = buttons,
            anchor = function()
                return self.input.title_bar.left_button.image.dimen
            end,
            modal = true,
        }
        UIManager:show(dialog)
    end
end)
