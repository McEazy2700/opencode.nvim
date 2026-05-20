local M = {}

function M.check()
  vim.health.start("opencode-cli.nvim")

  local config = require("opencode-cli.config")

  -- opencode binary
  local cmd = config.options and config.options.command or "opencode"
  if vim.fn.executable(cmd) == 1 then
    vim.health.ok(string.format("Binary '%s' is executable", cmd))
  else
    vim.health.error(string.format("Binary '%s' not found in PATH", cmd))
  end

  -- Neovim version (need 0.10+ for vim.system)
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.warn("Neovim < 0.10 detected — vim.system() may not be available")
  end

  -- Terminal state
  local term = require("opencode-cli.terminal")
  if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    vim.health.ok(string.format("Terminal is running (buf=%d, pid=%s)",
      term.buf, tostring(term._pid)))
  else
    vim.health.info("Terminal is not currently running")
  end

  -- Optional: snacks.nvim
  local provider = config.options and config.options.terminal.provider or "native"
  if provider == "snacks" then
    if pcall(require, "snacks") then
      vim.health.ok("snacks.nvim found (required for 'snacks' provider)")
    else
      vim.health.error("snacks.nvim not found — terminal.provider = 'snacks' will not work")
    end
  else
    if pcall(require, "snacks") then
      vim.health.info("snacks.nvim is available (set terminal.provider = 'snacks' to use it)")
    else
      vim.health.info("snacks.nvim not installed (optional)")
    end
  end

  -- Context placeholders
  local contexts = config.options and config.options.contexts or {}
  local count = vim.tbl_count(contexts)
  if count > 0 then
    local keys = vim.tbl_keys(contexts)
    table.sort(keys)
    vim.health.ok(string.format("%d context placeholders: %s", count, table.concat(keys, "  ")))
  else
    vim.health.warn("No context placeholders configured")
  end

  -- git (needed for @diff)
  if vim.fn.executable("git") == 1 then
    vim.health.ok("git is executable (@diff context will work)")
  else
    vim.health.warn("git not found — @diff context placeholder will return nil")
  end
end

return M
