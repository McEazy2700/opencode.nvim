local M = {}

---Global completion function for @placeholder names in vim.ui.input.
---Registered as a global so `completion = "customlist,v:lua.opencode_cli_completion"` works.
_G.opencode_cli_completion = function(ArgLead, CmdLine, CursorPos) -- luacheck: ignore
  local Context = require("opencode-cli.context")
  local placeholders = Context.placeholders()

  -- ArgLead doesn't always isolate the last word correctly, so parse from CmdLine
  local start_idx, end_idx = CmdLine:find("([^%s]+)$")
  local latest_word = start_idx and CmdLine:sub(start_idx, end_idx) or nil

  local items = {}
  for _, ph in ipairs(placeholders) do
    if not latest_word or ph:find(latest_word, 1, true) == 1 then
      local new_cmd = latest_word
        and (CmdLine:sub(1, start_idx - 1) .. ph .. CmdLine:sub(end_idx + 1))
        or  (CmdLine .. ph)
      table.insert(items, new_cmd)
    end
  end
  return items
end

---Open the ask input, capturing any visual selection as automatic context.
---If the prompt contains @placeholders those are rendered instead.
---@param cmd_opts? table
function M.ask(cmd_opts)
  cmd_opts = cmd_opts or {}

  local Context = require("opencode-cli.context")
  local ctx = Context.new()

  local sel_text, sel_range = ctx:selection_text()
  local path = vim.api.nvim_buf_get_name(ctx.buf)

  local config = require("opencode-cli.config")

  vim.ui.input({
    prompt     = config.options.ask.prompt,
    completion = "customlist,v:lua.opencode_cli_completion",
  }, function(input)
    if not input or input == "" then return end

    local has_placeholder = input:find("@", 1, true)
    local final

    if sel_text and not has_placeholder then
      -- No explicit @placeholder — prepend raw selection as code block
      final = string.format(
        "File: %s (lines %d-%d)\n```\n%s\n```\n\n%s",
        path,
        sel_range.from[1],
        sel_range.to[1],
        sel_text,
        input
      )
    else
      final = ctx:render(input)
    end

    require("opencode-cli.terminal").send(final)
  end)
end

---Show a picker to choose from predefined prompts or commands.
function M.select()
  local config  = require("opencode-cli.config")
  local Context = require("opencode-cli.context")
  local ctx     = Context.new()

  local items = {}

  if config.options.select.prompts then
    local sorted = {}
    for name, prompt in pairs(config.options.select.prompts) do
      table.insert(sorted, { type = "prompt", name = name, prompt = prompt })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    for _, item in ipairs(sorted) do table.insert(items, item) end
  end

  if config.options.select.commands then
    local sorted = {}
    for name, desc in pairs(config.options.select.commands) do
      table.insert(sorted, { type = "command", name = name, desc = desc })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    for _, item in ipairs(sorted) do table.insert(items, item) end
  end

  vim.ui.select(items, {
    prompt      = config.options.select.prompt or "opencode: ",
    format_item = function(item)
      if item.type == "prompt" then
        return string.format("[%-14s] %s", item.name, item.prompt)
      else
        return string.format("[%-14s] %s", item.name, item.desc or "")
      end
    end,
  }, function(choice)
    if not choice then return end

    if choice.type == "prompt" then
      local prompt = choice.prompt
      -- Ends with "..." → open ask UI with it as the default text
      if prompt:match("%.%.%.$") then
        M._ask_with_default(prompt:gsub("%.%.%.$", ""), ctx)
      else
        local rendered = ctx:render(prompt)
        require("opencode-cli.terminal").send(rendered)
      end
    elseif choice.type == "command" then
      require("opencode-cli.terminal").send("/" .. choice.name)
    end
  end)
end

---Open the ask input pre-filled with `default`.
---@param default string
---@param ctx? OpencodeContext
function M._ask_with_default(default, ctx)
  local config = require("opencode-cli.config")
  ctx = ctx or require("opencode-cli.context").new()

  vim.ui.input({
    prompt     = config.options.ask.prompt,
    default    = default,
    completion = "customlist,v:lua.opencode_cli_completion",
  }, function(input)
    if not input or input == "" then return end
    require("opencode-cli.terminal").send(ctx:render(input))
  end)
end

---Select from configured models and pass to the running terminal (or start with it).
function M.select_model()
  local config  = require("opencode-cli.config")
  local models  = config.options.models or {}
  if #models == 0 then
    vim.notify("opencode-cli: no models configured", vim.log.levels.WARN)
    return
  end

  vim.ui.select(models, { prompt = "Select opencode model: " }, function(choice)
    if not choice then return end
    local term = require("opencode-cli.terminal")
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      term.send("/model " .. choice)
    else
      term.open({ "--model", choice })
    end
  end)
end

return M
