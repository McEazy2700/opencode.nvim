local M = {}

local config = require("opencode.config")

M.buf = nil
M.win = nil
M._pid = nil

function M.open(args)
  local opts = config.options.terminal
  args = args or {}

  -- Toggle: if already open, hide the window
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      vim.api.nvim_win_close(M.win, true)
      M.win = nil
    else
      M.win = M.providers[opts.provider].open(M.buf)
    end
    return
  end

  M.buf = vim.api.nvim_create_buf(false, true)
  M.win = M.providers[opts.provider].open(M.buf)

  local cmd_parts = { config.options.command }
  for _, arg in ipairs(args) do
    table.insert(cmd_parts, arg)
  end

  local job_id = vim.fn.termopen(table.concat(cmd_parts, " "), {
    on_exit = function()
      if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_win_close(M.win, true)
        M.win = nil
      end
      M.buf = nil
      M._pid = nil
    end,
  })

  if job_id and job_id > 0 then
    local ok, pid = pcall(vim.fn.jobpid, job_id)
    if ok then M._pid = pid end
  end

  vim.api.nvim_set_option_value("number",         false, { scope = "local", win = M.win })
  vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = M.win })
  vim.api.nvim_set_option_value("signcolumn",     "no",  { scope = "local", win = M.win })
  vim.cmd("startinsert")
end

function M.close()
  if M._pid then
    M._terminate(M._pid)
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
  end
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
    M.buf = nil
  end
  M._pid = nil
end

function M._terminate(pid)
  if vim.fn.has("unix") == 1 then
    -- Negative PID kills the entire process group, including child processes
    os.execute("kill -TERM -" .. pid .. " 2>/dev/null")
  else
    pcall(vim.uv.kill, pid, "SIGTERM")
  end
end

---Send text to the running terminal via Bracketed Paste.
---Opens the terminal first if it is not yet running.
---@param text string
function M.send(text)
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    M.open()
    -- Wait for terminal to initialise before sending
    vim.defer_fn(function() M._send_raw(text) end, 150)
    return
  end
  M._send_raw(text)
end

function M._send_raw(text)
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then return end

  local chan = vim.b[M.buf].terminal_job_id
  if not chan then return end

  -- Escape leading $ on any line so the CLI doesn't interpret it as a shell command
  local escaped = text:gsub("\n%$", "\n $")
  if escaped:sub(1, 1) == "$" then
    escaped = " " .. escaped
  end

  vim.api.nvim_chan_send(chan, "\27[200~" .. escaped .. "\27[201~\n")

  if not (M.win and vim.api.nvim_win_is_valid(M.win)) then
    M.open()
  else
    vim.api.nvim_set_current_win(M.win)
    vim.cmd("startinsert")
  end
end

M.providers = {
  native = {
    open = function(buf)
      local opts = config.options.terminal
      local pos  = opts.position
      local size = opts.size
      local cmd  = (pos == "right" and "vsplit")
        or (pos == "left"   and "leftabove vsplit")
        or (pos == "top"    and "leftabove split")
        or "split"

      vim.cmd(cmd)
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)

      if pos == "right" or pos == "left" then
        vim.api.nvim_win_set_width(win, size)
      else
        vim.api.nvim_win_set_height(win, size)
      end
      return win
    end,
  },

  float = {
    open = function(buf)
      local fo     = config.options.terminal.float_opts
      local width  = math.floor(vim.o.columns * (fo.width  or 0.8))
      local height = math.floor(vim.o.lines   * (fo.height or 0.8))
      local row    = math.floor((vim.o.lines   - height) / 2)
      local col    = math.floor((vim.o.columns - width)  / 2)
      return vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width    = width,
        height   = height,
        row      = row,
        col      = col,
        style    = "minimal",
        border   = fo.border or "rounded",
      })
    end,
  },

  snacks = {
    open = function(buf)
      local ok, snacks = pcall(require, "snacks")
      if not ok then
        vim.notify("opencode: snacks.nvim not found, falling back to float", vim.log.levels.WARN)
        return M.providers.float.open(buf)
      end
      local fo  = config.options.terminal.float_opts
      local obj = snacks.win({
        buf      = buf,
        position = "float",
        width    = fo.width,
        height   = fo.height,
        border   = fo.border or "rounded",
        style    = "terminal",
      })
      return obj.win
    end,
  },
}

return M
