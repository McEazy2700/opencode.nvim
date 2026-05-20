local M = {}

function M.setup(opts)
  local config = require("opencode.config")
  M.config = config.setup(opts)

  local term = require("opencode.terminal")
  local cmds = require("opencode.commands")

  vim.api.nvim_create_user_command("Opencode", function()
    term.open()
  end, { desc = "Open/toggle opencode terminal" })

  vim.api.nvim_create_user_command("OpencodeAsk", function(o)
    cmds.ask(o)
  end, { range = true, desc = "Ask opencode (prepends visual selection if present)" })

  vim.api.nvim_create_user_command("OpencodeSelect", function()
    cmds.select()
  end, { desc = "Pick from opencode prompts and commands" })

  vim.api.nvim_create_user_command("OpencodeClose", function()
    term.close()
  end, { desc = "Close opencode terminal and stop the process" })

  if M.config.models and #M.config.models > 0 then
    vim.api.nvim_create_user_command("OpencodeSelectModel", function()
      cmds.select_model()
    end, { desc = "Switch opencode model" })
  end

  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      term.close()
    end,
  })
end

-- Convenience wrappers (usable from keymaps without going through the command layer)

function M.open()
  require("opencode.terminal").open()
end

function M.ask(opts)
  require("opencode.commands").ask(opts)
end

function M.select()
  require("opencode.commands").select()
end

function M.send(text)
  require("opencode.terminal").send(text)
end

return M
