---Context captured before opening an input prompt.
---Stores cursor/buf/selection state and provides @placeholder helpers.
---@class OpencodeContext
local Context = {}
Context.__index = Context

---@class OpencodeRange
---@field from integer[] {line, col} 1,0-based
---@field to   integer[] {line, col} 1,0-based
---@field kind "char"|"line"|"block"

---@param buf integer
---@return OpencodeRange|nil
local function capture_selection(buf)
  local mode = vim.fn.mode()
  local kind = (mode == "V" and "line")
    or (mode == "v" and "char")
    or (mode == "\22" and "block")
  if not kind then return nil end

  -- Exit visual so '</'> marks are consistent
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", true)

  local from = vim.api.nvim_buf_get_mark(buf, "<")
  local to   = vim.api.nvim_buf_get_mark(buf, ">")

  if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
    from, to = to, from
  end
  if kind == "block" and from[2] > to[2] then
    from[2], to[2] = to[2], from[2]
  end

  return { from = from, to = to, kind = kind }
end

---Create a new context capturing the current editor state.
function Context.new()
  local self  = setmetatable({}, Context)
  self.win    = vim.api.nvim_get_current_win()
  self.buf    = vim.api.nvim_get_current_buf()
  self.cursor = vim.api.nvim_win_get_cursor(self.win)
  self.range  = capture_selection(self.buf)
  return self
end

---Format a buffer or filepath reference for opencode (e.g. `~/foo.lua:L21:C10`).
---@param loc integer|string buffer number or filepath
---@param args? {start_line?:integer, start_col?:integer, end_line?:integer, end_col?:integer}
---@return string|nil
function Context.format(loc, args)
  local filepath = (type(loc) == "string" and loc)
    or (type(loc) == "number" and vim.api.nvim_buf_get_name(loc))
    or nil
  if not filepath or filepath == "" then return nil end

  local result = vim.fn.fnamemodify(filepath, ":p:~")

  if args and args.start_line then
    if args.end_line and args.start_line > args.end_line then
      args.start_line, args.end_line = args.end_line, args.start_line
      if args.start_col and args.end_col then
        args.start_col, args.end_col = args.end_col, args.start_col
      end
    end
    result = result .. ":" .. string.format("L%d", args.start_line)
    if args.start_col then
      result = result .. string.format(":C%d", args.start_col)
    end
    if args.end_line then
      result = result .. string.format("-L%d", args.end_line)
      if args.end_col then
        result = result .. string.format(":C%d", args.end_col)
      end
    end
  end

  return result
end

---Selection range if present, otherwise cursor position.
function Context:this()
  if self.range then
    return Context.format(self.buf, {
      start_line = self.range.from[1],
      start_col  = self.range.kind ~= "line" and self.range.from[2] or nil,
      end_line   = self.range.to[1],
      end_col    = self.range.kind ~= "line" and self.range.to[2] or nil,
    })
  end
  return Context.format(self.buf, {
    start_line = self.cursor[1],
    start_col  = self.cursor[2] + 1,
  })
end

---The current buffer path.
function Context:buffer()
  return Context.format(self.buf)
end

---All listed open buffers.
function Context:buffers()
  local files = {}
  for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local p = Context.format(b.bufnr)
    if p then table.insert(files, p) end
  end
  return #files > 0 and table.concat(files, ", ") or nil
end

---Visible line ranges across all windows.
function Context:visible_text()
  local parts = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local loc = Context.format(buf, {
      start_line = vim.fn.line("w0", win),
      end_line   = vim.fn.line("w$", win),
    })
    if loc then table.insert(parts, loc) end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

---Diagnostics in the current buffer.
function Context:diagnostics()
  local diags = vim.diagnostic.get(self.buf)
  if #diags == 0 then return nil end

  local lines = {}
  for _, d in ipairs(diags) do
    local loc = Context.format(self.buf, {
      start_line = d.lnum + 1,
      start_col  = d.col + 1,
    })
    table.insert(lines, string.format("- %s (%s): %s",
      loc or "?", d.source or "unknown", d.message:gsub("%s+", " ")))
  end

  return string.format("%d diagnostics:\n%s", #diags, table.concat(lines, "\n"))
end

---Quickfix list entries referencing files.
function Context:quickfix()
  local qflist = vim.fn.getqflist()
  if #qflist == 0 then return nil end
  local parts = {}
  for _, e in ipairs(qflist) do
    if e.bufnr ~= 0 then
      local loc = Context.format(e.bufnr, { start_line = e.lnum, start_col = e.col })
      if loc then table.insert(parts, loc) end
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

---Output of `git diff` from cwd.
function Context:git_diff()
  local result = vim.system({ "git", "--no-pager", "diff" }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout or result.stdout == "" then return nil end
  return result.stdout
end

---Plain-text (no-pattern) global string replacement.
local function str_replace(str, find, repl)
  local out = {}
  local i = 1
  while i <= #str do
    local j = str:find(find, i, true)
    if not j then
      table.insert(out, str:sub(i))
      break
    end
    table.insert(out, str:sub(i, j - 1))
    table.insert(out, repl)
    i = j + #find
  end
  return table.concat(out)
end

---Render @placeholders in `prompt` by calling their context functions.
---@param prompt string
---@return string rendered
function Context:render(prompt)
  local contexts = require("opencode.config").options.contexts
  local keys = vim.tbl_keys(contexts)
  -- Longer keys first to prevent @buffer matching before @buffers
  table.sort(keys, function(a, b) return #a > #b end)

  local result = prompt
  for _, k in ipairs(keys) do
    if result:find(k, 1, true) then
      local value = contexts[k](self)
      if value then
        result = str_replace(result, k, value)
      end
    end
  end
  return result
end

---Sorted list of all configured placeholder keys (for completion).
---@return string[]
function Context.placeholders()
  local keys = vim.tbl_keys(require("opencode.config").options.contexts)
  table.sort(keys)
  return keys
end

---Return the text of the visual selection and its range.
---@return string|nil text, OpencodeRange|nil range
function Context:selection_text()
  if not self.range then return nil, nil end

  local lines = vim.api.nvim_buf_get_lines(
    self.buf, self.range.from[1] - 1, self.range.to[1], false)
  if #lines == 0 then return nil, nil end

  if self.range.kind == "char" then
    if #lines == 1 then
      lines[1] = lines[1]:sub(self.range.from[2] + 1, self.range.to[2] + 1)
    else
      lines[1]      = lines[1]:sub(self.range.from[2] + 1)
      lines[#lines] = lines[#lines]:sub(1, self.range.to[2] + 1)
    end
  elseif self.range.kind == "block" then
    for i, line in ipairs(lines) do
      lines[i] = line:sub(self.range.from[2] + 1, self.range.to[2] + 1)
    end
  end

  return table.concat(lines, "\n"), self.range
end

return Context
