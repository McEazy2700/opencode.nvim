local M = {}

M.defaults = {
  command = "opencode",
  terminal = {
    provider = "native", -- "native", "float", "snacks"
    position = "right",  -- for native: "right", "left", "top", "bottom"
    size = 80,
    float_opts = {
      width = 0.8,
      height = 0.8,
      border = "rounded",
    },
  },
  -- @placeholder context functions injected into prompts
  contexts = {
    ["@this"]        = function(ctx) return ctx:this() end,
    ["@buffer"]      = function(ctx) return ctx:buffer() end,
    ["@buffers"]     = function(ctx) return ctx:buffers() end,
    ["@visible"]     = function(ctx) return ctx:visible_text() end,
    ["@diagnostics"] = function(ctx) return ctx:diagnostics() end,
    ["@quickfix"]    = function(ctx) return ctx:quickfix() end,
    ["@diff"]        = function(ctx) return ctx:git_diff() end,
  },
  ask = {
    prompt = "Ask opencode: ",
  },
  select = {
    prompt = "opencode: ",
    -- End with "..." to open ask UI with it as default instead of submitting directly
    prompts = {
      ask      = "...",
      explain  = "Explain @this and its context",
      document = "Add comments documenting @this",
      fix      = "Fix @diagnostics",
      review   = "Review @this for correctness and readability",
      optimize = "Optimize @this for performance and readability",
      test     = "Add tests for @this",
      diff     = "Review the following git diff for correctness: @diff",
    },
    commands = {
      new    = "Start a new session",
      resume = "Resume the last session",
    },
  },
  -- Optional: list of models for :OpencodeSelectModel
  models = {},
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
