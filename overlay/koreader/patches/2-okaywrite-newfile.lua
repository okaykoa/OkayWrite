-- OkayWrite: add a "New file" action to the FileManager "+" menu, directly
-- above the existing "New folder" entry. Delegates to the Text editor plugin's
-- newFile() so the file opens in the editor after creation.

local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local userpatch = require("userpatch")
local _ = require("gettext")

-- Capture the texteditor plugin instance (re-instantiated per FM/Reader spin-up).
local texteditor
userpatch.registerPatchPluginFunc("texteditor", function(plugin)
  texteditor = plugin
end)

local orig_getPlusDialogButtons = FileManager.getPlusDialogButtons
FileManager.getPlusDialogButtons = function(self)
  local title, buttons = orig_getPlusDialogButtons(self)
  if self.selected_files then
    return title, buttons -- leave multi-select menu untouched
  end

  local folder = self.file_chooser and self.file_chooser.path
  local new_file_row = { {
    text = _("New file"),
    callback = function()
      if self.plus_dialog then UIManager:close(self.plus_dialog) end
      if texteditor and folder then
        texteditor:newFile(folder .. "/")
      end
    end,
  } }

  -- Insert "New file" immediately before the "New folder" row; if not found
  -- (e.g. unexpected localization), fall back to inserting at the top.
  local label = _("New folder")
  local inserted = false
  for i, row in ipairs(buttons) do
    if row[1] and row[1].text == label then
      table.insert(buttons, i, new_file_row)
      inserted = true
      break
    end
  end
  if not inserted then
    table.insert(buttons, 1, new_file_row)
  end

  return title, buttons
end
