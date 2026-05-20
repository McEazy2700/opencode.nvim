# opencode.nvim

A Neovim plugin for [opencode](https://opencode.ai) — the AI coding assistant.

Runs `opencode` in a managed terminal window and adds a context-aware prompting layer:
type `@this`, `@diagnostics`, `@diff` (and more) directly in your prompts to inject
live editor state before the text is sent.

---

## Features

- **Terminal management** — open, toggle, and close `opencode` in a split, float, or [snacks.nvim](https://github.com/folke/snacks.nvim) window
- **`@placeholder` contexts** — `@this`, `@buffer`, `@buffers`, `@visible`, `@diagnostics`, `@quickfix`, `@diff` are resolved to real file/line references or content before sending
- **Ask UI** — `<Tab>`-completion for placeholders; visual selections are auto-included when no `@` is used
- **Select menu** — pick from predefined prompts or send `/commands` via `vim.ui.select`
- **Clean process teardown** — sends `SIGTERM` to the entire `opencode` process group on exit

---

## Requirements

- Neovim >= 0.10
- [`opencode`](https://opencode.ai) installed and on your `$PATH`
- **Optional:** [snacks.nvim](https://github.com/folke/snacks.nvim) for the `snacks` terminal provider

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "McEazy2700/opencode.nvim",
  config = function()
    require("opencode").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "McEazy2700/opencode.nvim",
  config = function()
    require("opencode").setup()
  end,
}
```

---

## Setup

Call `setup()` once in your config. All options are optional.

```lua
require("opencode").setup({
  -- The opencode binary name or absolute path
  command = "opencode",

  terminal = {
    provider = "native",  -- "native" | "float" | "snacks"
    position = "right",   -- native only: "right" | "left" | "top" | "bottom"
    size     = 80,        -- native only: width (right/left) or height (top/bottom)
    float_opts = {
      width  = 0.8,       -- fraction of editor width
      height = 0.8,       -- fraction of editor height
      border = "rounded",
    },
  },

  -- @placeholder context functions. Each receives the Context object and
  -- returns a string (injected into the prompt) or nil (placeholder left as-is).
  -- Add, remove, or override any of these.
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
    -- Predefined prompts shown in :OpencodeSelect.
    -- End with "..." to open the ask UI with it as the default text instead of sending immediately.
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
    -- /commands sent to the terminal when selected
    commands = {
      new    = "Start a new session",
      resume = "Resume the last session",
    },
  },

  -- Populate to enable :OpencodeSelectModel
  models = {},
})
```

---

## Commands

| Command | Description |
|---|---|
| `:Opencode` | Open or toggle the `opencode` terminal |
| `:OpencodeAsk` | Open the ask input (works in normal and visual mode) |
| `:OpencodeSelect` | Open the prompt/command picker |
| `:OpencodeClose` | Close the terminal and stop the process |
| `:OpencodeSelectModel` | Switch model (requires `models` to be configured) |

---

## Keymaps

No keymaps are set by default. Suggested bindings:

```lua
local map = vim.keymap.set

-- Open / toggle the terminal
map("n", "<leader>oc", "<cmd>Opencode<cr>",       { desc = "opencode: toggle" })

-- Ask from normal mode (no selection)
map("n", "<leader>oa", "<cmd>OpencodeAsk<cr>",    { desc = "opencode: ask" })

-- Ask with visual selection as context
map("v", "<leader>oa", "<cmd>OpencodeAsk<cr>",    { desc = "opencode: ask selection" })

-- Prompt / command picker
map("n", "<leader>os", "<cmd>OpencodeSelect<cr>", { desc = "opencode: select" })
```

---

## Context placeholders

Placeholders are resolved just before the prompt is sent. They expand to file
path references that `opencode` understands natively.

| Placeholder | Expands to |
|---|---|
| `@this` | Selection range (or cursor position) in the current file |
| `@buffer` | Path of the current buffer |
| `@buffers` | Paths of all listed buffers |
| `@visible` | Visible line ranges across all open windows |
| `@diagnostics` | LSP/diagnostic messages for the current buffer |
| `@quickfix` | Current quickfix list entries |
| `@diff` | Output of `git diff` from the working directory |

**Example prompts:**

```
Fix @diagnostics
Explain @this and its context
Review the following git diff: @diff
Add tests for @this
```

### Custom contexts

Any function that returns a string can be a context:

```lua
require("opencode").setup({
  contexts = {
    -- Built-ins (keep or override as needed)
    ["@this"]        = function(ctx) return ctx:this() end,

    -- Add your own
    ["@todo"] = function(_ctx)
      local lines = {}
      for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
        for _, line in ipairs(vim.api.nvim_buf_get_lines(buf.bufnr, 0, -1, false)) do
          if line:match("TODO") then table.insert(lines, line) end
        end
      end
      return #lines > 0 and table.concat(lines, "\n") or nil
    end,
  },
})
```

---

## Ask UI

`:OpencodeAsk` opens a `vim.ui.input` prompt.

- **`<Tab>`** — complete `@placeholder` names
- **Visual selection** — if text is selected and the prompt contains no `@`, the
  selection is automatically prepended as a fenced code block with the file path and
  line range
- **`@placeholders`** — when typed explicitly, the selection is _not_ prepended;
  the placeholders are resolved instead

---

## Select menu

`:OpencodeSelect` opens a `vim.ui.select` picker with two sections:

- **Prompts** — predefined templates. Selecting one renders its placeholders and
  sends it immediately. A prompt ending in `...` opens the ask UI with it as
  the pre-filled default (useful for prompts you want to customise before sending).
- **Commands** — items send `/command` to the running terminal.

---

## Health check

```
:checkhealth opencode
```

Verifies the binary, Neovim version, terminal state, snacks availability,
configured placeholders, and `git`.

---

## Programmatic API

```lua
local oc = require("opencode")

oc.open()           -- open / toggle terminal
oc.ask()            -- open ask input
oc.select()         -- open select picker
oc.send("Fix @diagnostics")  -- render and send a prompt directly
```
