-- Neovim "Feels like VS Code" (Kitty + tmux friendly)
-- Tip: in Kitty set: macos_cmd_modifier ctrl
-- Then press Cmd+P / Cmd+Shift+F / Cmd+B / Cmd+` etc.

-- Version check: many plugins require 0.10+
local nvim_010 = vim.fn.has("nvim-0.10") == 1
if not nvim_010 then
  vim.notify("Zephyrus: Neovim 0.10+ recommended. Some plugins will be disabled.", vim.log.levels.WARN)
end

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ---------- Basics ----------
local opt = vim.opt
opt.number = true
opt.relativenumber = false
opt.cursorline = true
opt.termguicolors = true
opt.signcolumn = "yes"
opt.wrap = false
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.scrolloff = 6
opt.sidescrolloff = 6
opt.updatetime = 200
opt.timeoutlen = 400
opt.mouse = "a"
opt.clipboard = "unnamedplus"

-- Use NvimTree, not netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.splitright = true -- vertical splits open to the right
vim.opt.splitbelow = true -- horizontal splits open below

local map = vim.keymap.set
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("i", "jj", "<Esc>", { desc = "Exit insert" })

-- Normal mode word jumps with Option/Alt
vim.keymap.set('n', '<A-Left>', 'b')
vim.keymap.set('n', '<A-Right>', 'w')

-- Insert mode word jumps (hold Alt)
vim.keymap.set('i', '<A-Left>', '<C-Left>', { silent = true })
vim.keymap.set('i', '<A-Right>', '<C-Right>', { silent = true })

-- Cmd+Left/Right → line start/end
vim.keymap.set({ 'n', 'i' }, '<D-Left>', function()
  return vim.api.nvim_get_mode().mode == 'i' and '<Home>' or '^'
end, { expr = true })
vim.keymap.set({ 'n', 'i' }, '<D-Right>', function()
  return vim.api.nvim_get_mode().mode == 'i' and '<End>' or '$'
end, { expr = true })

-- PageUp/Down inside nvim
vim.keymap.set({ 'n', 'v' }, '<PageUp>', '<C-b>', { silent = true })
vim.keymap.set({ 'n', 'v' }, '<PageDown>', '<C-f>', { silent = true })

-- VS Code–style “quick fix”: Alt+.
vim.keymap.set({ "n", "v" }, "<M-.>", vim.lsp.buf.code_action, { desc = "Code Action (Alt+.)" })

-- OpenAI Codex
vim.keymap.set("n", "<leader>cc", function() require("codex").toggle() end, { desc = "Codex: Toggle" })
vim.keymap.set("v", "<leader>cs", function() require("codex").actions.send_selection() end,
  { desc = "Codex: Send selection" })


-- Toggle terminal (VS Code-ish)
vim.keymap.set({ "n", "t" }, "<D-j>", function()
  require("toggleterm").toggle(1)
  vim.cmd("wincmd J")
  vim.cmd("resize 12")
end, { desc = "Toggle bottom terminal" })

-- ---------- Detect zephyrus root dynamically ----------
-- Derive from this file's real path: {repo}/nvim/init.lua -> {repo}
local _this = debug.getinfo(1, "S").source:sub(2)
local zeph_root = vim.fn.fnamemodify(vim.fn.resolve(_this), ":h:h")
local zeph_nvim_plugin = zeph_root .. "/nvim-plugin"

-- ---------- lazy.nvim bootstrap ----------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Core libs / UX
  { "nvim-lua/plenary.nvim",      lazy = true },
  { "nvim-tree/nvim-web-devicons" },
  { "folke/which-key.nvim",       opts = {} },
  { "stevearc/dressing.nvim",     opts = {} }, -- nicer pickers
  { "j-hui/fidget.nvim",          opts = {} }, -- LSP progress
  {
    "folke/noice.nvim",
    cond = nvim_010,
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      presets = { bottom_search = true, command_palette = true },
      lsp = { progress = { enabled = false } }
    }, -- fidget handles progress
  },

  -- Zephyrus nvim-plugin (auto-detected from ~/.config/zephyrus symlink)
  { dir = zeph_nvim_plugin, lazy = false },

  -- Markdown and various other parsers
  {
    "OXY2DEV/markview.nvim",
    lazy = false,
    cond = nvim_010,
  },

  -- Science Editing
  {
    'goerz/jupytext.nvim',
    version = '0.2.0',
    opts = {},
  },

  {
    "quarto-dev/quarto-nvim",
    cond = nvim_010,
    dependencies = {
      "jmbuhr/otter.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
  },

  -- Documentation Generation
  {
    "danymat/neogen",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    cmd = "Neogen",
    keys = {
      { "<leader>ng", function() require("neogen").generate() end, desc = "Neogen: generate docstring" },
    },
    opts = {
      enabled = true,
      input_after_comment = true,
      languages = {
        python = {
          template = {
            annotation_convention = "google_docstrings",
          },
        },
      },
    },
  },

  {
    "NickvanDyke/opencode.nvim",
    dependencies = {
      ---@module 'snacks'
      { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {}

      vim.o.autoread = true

      vim.keymap.set({ "n", "x" }, "<C-a>", function() require("opencode").ask("@this: ", { submit = true }) end,
        { desc = "Ask opencode" })
      vim.keymap.set({ "n", "x" }, "<C-x>", function() require("opencode").select() end,
        { desc = "Execute opencode action…" })
      vim.keymap.set({ "n", "x" }, "ga", function() require("opencode").prompt("@this") end, { desc = "Add to opencode" })
      vim.keymap.set({ "n", "t" }, "<C-.>", function() require("opencode").toggle() end, { desc = "Toggle opencode" })
      vim.keymap.set("n", "<S-C-u>", function() require("opencode").command("session.half.page.up") end,
        { desc = "opencode half page up" })
      vim.keymap.set("n", "<S-C-d>", function() require("opencode").command("session.half.page.down") end,
        { desc = "opencode half page down" })
      vim.keymap.set('n', '+', '<C-a>', { desc = 'Increment', noremap = true })
      vim.keymap.set('n', '-', '<C-x>', { desc = 'Decrement', noremap = true })
    end,
  },

  -- OpenAI Codex
  {
    "rhart92/codex.nvim",
    opts = {
      split = "float",
      size = 0.3,
      float = {
        width = 0.6,
        height = 0.6,
        border = "rounded",
        row = nil,
        col = nil,
        title = "Codex",
      },
      codex_cmd = { "codex" },
      focus_after_send = false,
      log_level = "warn",
      autostart = false,
    },
  },


  -- Claude Code --
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    keys = {
      { "<leader>a",  nil,                              desc = "AI/Claude Code" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>",            desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>",       desc = "Focus Claude" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>",   desc = "Resume Claude" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>",       desc = "Add current buffer" },
      {
        "<leader>as",
        "<cmd>ClaudeCodeSend<cr>",
        mode = "v",
        desc = "Send selection to Claude",
      },
      {
        "<leader>as",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file to Claude",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
      },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>",   desc = "Deny diff" },
    },

    config = function()
      require("claudecode").setup({
        terminal = {
          provider = "auto",  -- Snacks if available, else fallback float

          snacks_win_opts = { -- Right-pinned float
            position = "right",
            width = 0.40,
            height = 1.0,
            border = "rounded",
            title = " Claude ",
            title_pos = "center",
            zindex = 50,
            keys = {
              -- Keep ESC inside Claude; close panel ONLY with `q` (normal mode)
              claude_close = {
                "q",
                "close",
                mode = "n",
                desc = "Close Claude panel",
              },
            },
          },

          -- Fallback if Snacks is missing
          native_float = {
            side = "right",
            width = 0.40,
            height = 1.0,
            border = "rounded",
            title = " Claude ",
          },

          auto_close = true,
        },
      })

      -- QoL: Look + scroll behavior for Claude panel
      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*claude*",
        callback = function(ev)
          vim.bo[ev.buf].scrollback = 100000 -- independent history
          vim.wo[0].number = false
          vim.wo[0].relativenumber = false
          vim.wo[0].signcolumn = "no"
          vim.wo[0].winfixwidth = true -- keep right-side width locked
        end,
      })
    end,
  },


  -- Treesitter (syntax, AST, motions) — many plugins depend on it
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      highlight        = { enable = true },
      indent           = { enable = true },
      ensure_installed = {
        "bash", "c", "cpp", "css", "diff", "dockerfile",
        "go", "gomod", "gosum", "html", "http", "javascript", "typescript", "tsx",
        "json", "jsonc", "lua", "make", "markdown", "markdown_inline",
        "python", "regex", "rust", "sql", "terraform", "toml", "vim", "vimdoc", "yaml"
      },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },

  -- (optional but useful for motions/selection powered by TS)
  { "nvim-treesitter/nvim-treesitter-textobjects" },

  -- Theme: VS Code
  {
    "Mofiqul/vscode.nvim",
    priority = 1000,
    config = function()
      require("vscode").setup({ transparent = false, italic_comments = true })
      vim.cmd.colorscheme("vscode")
    end
  },

  -- Statusline & Tabline
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require("lualine").setup({ options = { theme = "vscode", icons_enabled = true } })
    end
  },
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    opts = { options = { diagnostics = "nvim_lsp", show_buffer_close_icons = false } }
  },

  -- Explorer (sidebar)

  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        hidden = false,
        ignore = false,
      },
    },
  },

  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      filters = {
        dotfiles = false,
        git_ignored = false,
      },
      view = { side = "left", width = 34, preserve_window_proportions = true },
      actions = {
        open_file = {
          quit_on_open = false,
          window_picker = { enable = false }, -- ensure real split is created
        },
      },
      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        -- load defaults first
        api.config.mappings.default_on_attach(bufnr)

        -- kill default 's' (system_open → macOS open)
        pcall(vim.keymap.del, "n", "s", { buffer = bufnr })

        local function map(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, {
            buffer = bufnr, noremap = true, silent = true, nowait = true, desc = desc
          })
        end

        -- non-conflicting, no-prefix split keys
        map("S", api.node.open.horizontal, "Open: split (below)")
        map("V", api.node.open.vertical, "Open: vsplit (right)")
        map("-", api.node.open.horizontal, "Open: split (below)")
        map("<C-s>", api.node.open.horizontal, "Open: split (below)")
        map("<C-v>", api.node.open.vertical, "Open: vsplit (right)")
        -- leave 'v' alone (your submenu), and avoid '\' if you keep it as localleader
      end,
    },
  },

  -- Telescope: Quick Open / Search / Commands
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local tb = require("telescope.builtin")
      map("n", "<C-p>", tb.find_files, { desc = "Quick Open" })         -- Cmd+P
      map("n", "<C-S-f>", tb.live_grep, { desc = "Search in project" }) -- Cmd+Shift+F
      map("n", "<C-S-p>", tb.commands, { desc = "Command palette" })    -- Cmd+Shift+P
      map("n", "<leader>p", tb.find_files, { desc = "Find files" })
      map("n", "<leader>f", tb.live_grep, { desc = "Live grep" })
    end
  },
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build = "make",
    config = function() pcall(function() require("telescope").load_extension("fzf") end) end
  },

  -- Outline / Symbols (Cmd+Shift+O ⇒ map to <C-S-o>)
  {
    "stevearc/aerial.nvim",
    opts = { backends = { "lsp", "treesitter", "markdown" }, layout = { max_width = { 40, 0.25 } } },
    keys = {
      { "<C-S-o>",   "<cmd>AerialToggle!<cr>", desc = "Outline (Cmd+Shift+O)" },
      { "<leader>o", "<cmd>AerialToggle!<cr>", desc = "Outline" },
    }
  },

  -- Breadcrumbs
  { "SmiteshP/nvim-navic",                        lazy = true },
  {
    "utilyre/barbecue.nvim",
    name = "barbecue",
    version = "*",
    dependencies = { "SmiteshP/nvim-navic", "nvim-tree/nvim-web-devicons" },
    opts = {}
  },

  -- Problems / Diagnostics
  {
    "folke/trouble.nvim",
    cond = nvim_010,
    opts = {},
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics panel" },
    },
    cmd = "Trouble",
  },

  -- Git
  { "lewis6991/gitsigns.nvim",             opts = {} },
  { "sindrets/diffview.nvim",              dependencies = "nvim-lua/plenary.nvim" },

  -- Editing niceties
  { "numToStr/Comment.nvim",               opts = {} },
  { "tpope/vim-surround" },
  { "windwp/nvim-autopairs",               opts = {} },
  { "lukas-reineke/indent-blankline.nvim", main = "ibl",                          opts = {} },
  { "folke/todo-comments.nvim",            opts = {} },
  { "mg979/vim-visual-multi" }, -- multi-cursor

  -- Terminal like VS Code (toggle terminal)
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    opts = { open_mapping = [[<c-`>]], shade_terminals = true, direction = "horizontal" },
    config = function(_, opts)
      require("toggleterm").setup(opts)
      map({ "n", "t" }, "<C-`>", "<cmd>ToggleTerm<cr>", { desc = "Toggle terminal (Cmd+` via Kitty)" })
    end
  },

  -- Minimap
  {
    "gorbit99/codewindow.nvim",
    cond = nvim_010,
    config = function()
      local codewindow = require("codewindow")
      codewindow.setup()
      codewindow.apply_default_keybinds() -- <leader>mm to toggle
    end
  },

  -- LSP + Mason + CMP (require 0.10+)
  { "williamboman/mason.nvim",          config = true, cond = nvim_010 },
  { "williamboman/mason-lspconfig.nvim", cond = nvim_010 },
  { "neovim/nvim-lspconfig",            cond = nvim_010 },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer", "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip", "saadparwaiz1/cmp_luasnip", "rafamadriz/friendly-snippets"
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()
      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<Tab>"]     = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"]   = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" }, { name = "luasnip" }, { name = "buffer" }, { name = "path" },
        }),
      })
    end
  },

  -- Formatting + Linting
  {
    "stevearc/conform.nvim",
    opts = {
      format_on_save = { timeout_ms = 2000, lsp_fallback = true },
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        javascript = { "prettier", "eslint_d" },
        typescript = { "prettier", "eslint_d" },
        javascriptreact = { "prettier", "eslint_d" },
        typescriptreact = { "prettier", "eslint_d" },
        css = { "prettier" },
        html = { "prettier" },
        json = { "jq" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        terraform = { "terraform_fmt" },
        go = { "gofmt", "goimports" },
        rust = { "rustfmt" },
        sh = { "shfmt" },
        sql = { "sqlfluff" },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        python = { "ruff" },
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescriptreact = { "eslint_d" },
        go = { "revive" },
        yaml = { "yamllint" },
        dockerfile = { "hadolint" },
        markdown = { "markdownlint" },
        terraform = { "tflint" },
        sql = { "sqlfluff" },
      }
      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
        callback = function() require("lint").try_lint() end,
      })
    end
  },

  -- YAML schemas (K8s, etc.)
  { "b0o/SchemaStore.nvim" },
  { "qvalentin/helm-ls.nvim", ft = "helm" },

  -- Debugging (DAP)
  -- Debug Adapter Protocol core
  { "mfussenegger/nvim-dap" },

  -- REQUIRED dep for dap-ui (many errors are from this missing)
  { "nvim-neotest/nvim-nio" },

  -- UI for DAP, loaded lazily and guarded
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    event = "VeryLazy", -- don't initialize at startup
    config = function()
      local ok_dap, dap = pcall(require, "dap")
      local ok_ui, dapui = pcall(require, "dapui")
      if not (ok_dap and ok_ui) then return end

      dapui.setup()

      -- Only open UI when a real debug session starts; close on exit/terminate
      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"]     = function() dapui.close() end
    end,
  },

  -- (optional) auto-install debuggers via Mason
  {
    "jay-babu/mason-nvim-dap.nvim",
    dependencies = { "williamboman/mason.nvim", "mfussenegger/nvim-dap" },
    opts = {
      ensure_installed = { "python", "delve", "js" },
      automatic_installation = true,
      handlers = {},
    },
  },

  -- Lightbulb silly little addon thing
  {
    "kosayoda/nvim-lightbulb",
    opts = { autocmd = { enabled = true }, sign = { enabled = true } },
  },

  {
    "folke/trouble.nvim",
    cond = nvim_010,
    opts = {},
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",              desc = "Problems (workspace)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Problems (file)" },
    },
  }

})

---------- LazyGit --------------
-- Open LazyGit in its own float (no ToggleTerm)
local function open_lazygit_float()
  if vim.fn.executable("lazygit") == 0 then
    vim.notify("lazygit not found in PATH", vim.log.levels.ERROR); return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local cols, lines = vim.o.columns, vim.o.lines
  local w = math.floor(cols * 0.75)
  local h = math.floor(lines * 0.75)
  local row = math.floor((lines - h) / 2 - 1)
  local col = math.floor((cols - w) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = w,
    height = h,
    row = row,
    col = col,
  })

  -- launch lazygit
  vim.fn.termopen("lazygit", { on_exit = function() pcall(vim.api.nvim_win_close, win, true) end })
  vim.cmd.startinsert()

  -- close with q or Esc
  local opts = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("t", "<C-q>", "<C-\\><C-n>:close<CR>", opts)
  -- vim.keymap.set("t", "<Esc>", "<C-\\><C-n>:close<CR>", opts)
end

vim.keymap.set("n", "<leader>gg", open_lazygit_float, { desc = "LazyGit (float)" })


---------- K9s -----------------

-- ─────────────────────────────────────────────────────────────────────────────
-- K9s in a centered floating terminal (no ToggleTerm; Esc is NOT captured)
-- ─────────────────────────────────────────────────────────────────────────────
local function k9s_float(opts)
  if vim.fn.executable("k9s") == 0 then
    vim.notify("k9s not found in PATH", vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local args = { "k9s" }
  if opts.namespace and #opts.namespace > 0 then
    vim.list_extend(args, { "-n", opts.namespace })
  end
  if opts.context and #opts.context > 0 then
    vim.list_extend(args, { "--context", opts.context })
  end

  -- scratch term buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- helper to (re)center the float
  local function win_config()
    local cols, lines = vim.o.columns, vim.o.lines
    local w = math.floor(cols * 0.90)
    local h = math.floor(lines * 0.90)
    return {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      width = w,
      height = h,
      row = math.floor((lines - h) / 2 - 1),
      col = math.floor((cols - w) / 2),
    }
  end

  local win = vim.api.nvim_open_win(buf, true, win_config())

  -- launch k9s
  local job = vim.fn.termopen(args, {
    on_exit = function()
      if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
      if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
    end
  })
  if job <= 0 then
    vim.notify("Failed to start k9s", vim.log.levels.ERROR)
    return
  end
  vim.cmd.startinsert()

  -- close ONLY with "q" (Esc is left to k9s)
  vim.keymap.set("t", "q", "<C-\\><C-n>:close<CR>", { buffer = buf, noremap = true, silent = true })

  -- keep float centered on :resize / terminal resize
  vim.api.nvim_create_autocmd("VimResized", {
    buffer = buf,
    callback = function()
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_config, win, win_config())
      end
    end,
  })
end

-- Keymaps:
--   <leader>kk → open k9s float
--   <leader>kn → pick namespace then open
--   <leader>kc → pick context then open
vim.keymap.set("n", "<leader>kk", function()
  k9s_float()
end, { desc = "K9s (float)" })

vim.keymap.set("n", "<leader>kn", function()
  vim.ui.input({ prompt = "Namespace (blank = all): " }, function(ns)
    k9s_float({ namespace = ns or "" })
  end)
end, { desc = "K9s (namespace…)" })

vim.keymap.set("n", "<leader>kc", function()
  local cur = (vim.fn.systemlist("kubectl config current-context")[1] or ""):gsub("%s+$", "")
  vim.ui.input({ prompt = "Context: ", default = cur }, function(ctx)
    k9s_float({ context = ctx or "" })
  end)
end, { desc = "K9s (context…)" })


---------- LSP servers (require 0.10+) ----------
if nvim_010 then
  local lsp = require("lspconfig")
  local mason = require("mason")
  local mason_lsp = require("mason-lspconfig")

  mason.setup()
  mason_lsp.setup({
    ensure_installed = {
      "ts_ls", "html", "cssls", "eslint",
      "gopls", "rust_analyzer",
      "clangd",
      "yamlls", "jsonls",
      "dockerls", "docker_compose_language_service",
      "bashls", "terraformls", "lua_ls", "marksman", "sqlls", "helm_ls",
    },
    automatic_installation = true,
  })

  local cmp_cap = require("cmp_nvim_lsp").default_capabilities()
  local on_attach = function(client, bufnr)
    local nmap = function(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc }) end
    nmap("gd", vim.lsp.buf.definition, "Go to Definition")
    nmap("gr", vim.lsp.buf.references, "References")
    nmap("gD", vim.lsp.buf.declaration, "Declaration")
    nmap("gi", vim.lsp.buf.implementation, "Implementation")
    nmap("K", vim.lsp.buf.hover, "Hover")
    nmap("<F2>", vim.lsp.buf.rename, "Rename (F2)")
    nmap("<leader>rn", vim.lsp.buf.rename, "Rename")
    nmap("<leader>ca", vim.lsp.buf.code_action, "Code Action")
    nmap("<leader>f", function() require("conform").format({ async = true }) end, "Format")
    -- breadcrumbs
    pcall(function()
      local navic = require("nvim-navic")
      if client.server_capabilities.documentSymbolProvider then
        navic.attach(client, bufnr)
      end
    end)
  end

  -- YAML with SchemaStore (K8s etc.)
  lsp.yamlls.setup({
    on_attach = on_attach,
    capabilities = cmp_cap,
    settings = {
      yaml = {
        schemaStore = { enable = false, url = "" },
        schemas = require("schemastore").yaml.schemas(),
        format = { enable = true },
        validate = true,
        hover = true,
        completion = true,
      }
    }
  })

  -- Rust: clippy on save
  lsp.rust_analyzer.setup({
    on_attach = on_attach,
    capabilities = cmp_cap,
    settings = { ["rust-analyzer"] = { check = { command = "clippy" } } }
  })

  -- Others
  for _, name in ipairs({
    "ts_ls", "html", "cssls", "eslint", "gopls", "clangd", "jsonls",
    "dockerls", "docker_compose_language_service", "bashls", "terraformls", "lua_ls", "marksman", "sqlls", "helm_ls"
  }) do
    if name ~= "yamlls" and lsp[name] then
      lsp[name].setup({ on_attach = on_attach, capabilities = cmp_cap })
    end
  end
end -- nvim_010

-- ---------- VS Code-like keymaps (use Cmd in Kitty → Ctrl in Neovim) ----------
map("n", "<C-p>", "<cmd>Telescope find_files<cr>", { desc = "Quick Open" })      -- Cmd+P
map("n", "<C-S-f>", "<cmd>Telescope live_grep<cr>", { desc = "Search project" }) -- Cmd+Shift+F
map("n", "<C-S-p>", "<cmd>Telescope commands<cr>", { desc = "Command palette" }) -- Cmd+Shift+P
map("n", "<C-b>", "<cmd>NvimTreeToggle<cr>", { desc = "Explorer" })              -- Cmd+B
map({ "n", "x" }, "<C-/>", function()
  require("Comment.api").toggle.linewise.current()
end, { desc = "Toggle comment" })                                               -- Cmd+/
map({ "n", "t" }, "<C-`>", "<cmd>ToggleTerm<cr>", { desc = "Toggle terminal" }) -- Cmd+`

-- Focus areas (Explorer / Editor / Outline / Problems / Terminal)
map("n", "<leader>1", function() require("nvim-tree.api").tree.focus() end, { desc = "Focus Explorer" })
map("n", "<leader>2", "<C-w>w", { desc = "Focus Editor" })
map("n", "<leader>3", "<cmd>AerialOpen<cr>", { desc = "Focus Outline" })
if nvim_010 then
  map("n", "<leader>4", "<cmd>Trouble diagnostics toggle focus=true<cr>", { desc = "Focus Problems" })
end

-- ---------- IDE layout ----------
vim.api.nvim_create_user_command("IDE", function()
  vim.cmd("NvimTreeOpen")
  vim.cmd("wincmd l") -- go to editor
  pcall(function() require("aerial").open({ direction = "right" }) end)
  pcall(function() require("trouble").open("diagnostics") end)
  pcall(function() require("toggleterm").toggle(1) end)
  vim.cmd("wincmd J")             -- ensure terminal at bottom
  vim.cmd("resize 12")
  pcall(function() require("codewindow").open_minimap() end)
end, {})

-- Auto apply layout when opening a folder (nvim .)
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function(data)
    if vim.fn.isdirectory(data.file) == 1 then
      vim.cmd.cd(data.file)
      vim.defer_fn(function() vim.cmd("IDE") end, 100)
    end
  end,
})

-- Keep breadcrumbs updating
pcall(function()
  require("barbecue").setup({ create_autocmd = false })
  vim.api.nvim_create_autocmd(
    { "WinResized", "BufWinEnter", "CursorHold", "InsertLeave", "BufModifiedSet" },
    { callback = function() pcall(require("barbecue.ui").update) end }
  )
end)

-- Predictable split direction
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Never split the file tree window; keep it a fixed-width sidebar
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "NvimTree", "neo-tree" },
  callback = function()
    vim.wo.winfixwidth = true
  end,
})

-- If you're using nvim-tree, this avoids weird window picking on open
pcall(function()
  require("nvim-tree").setup({
    actions = {
      open_file = {
        window_picker = { enable = false }, -- open files in the current editor window
      },
    },
    view = { side = "left", width = 34 },
  })
end)

-- Helper: ensure we’re on a real editor window (not tree/outline/quickfix) before splitting
local function focus_editor_window()
  local special = { NvimTree = true, ["neo-tree"] = true, aerial = true, qf = true, help = true, ["toggleterm"] = true }
  local ft = vim.bo.filetype
  if special[ft] then
    -- try stepping right; if still special, scan all windows for a non-special
    vim.cmd("wincmd l")
    if special[vim.bo.filetype] then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local sft = vim.bo[buf].filetype
        if not special[sft] then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end
  end
end

-- 4) Muscle-memory keys that ALWAYS split the editor pane (never the tree)
vim.keymap.set("n", "<leader>v", function() -- vertical split (right)
  focus_editor_window()
  vim.cmd("vsplit")
end, { desc = "Vertical split (editor)" })

vim.keymap.set("n", "<leader>-", function() -- horizontal split (below)
  focus_editor_window()
  vim.cmd("split")
end, { desc = "Horizontal split (editor)" })

-- One statusline for the whole UI (bottom), but per-window titles at the top
vim.opt.laststatus = 3  -- global statusline
vim.opt.showtabline = 1 -- only show tabline when >1 tab

-- Highlight (optional)
vim.api.nvim_set_hl(0, "WinBar", { link = "StatusLine" })
vim.api.nvim_set_hl(0, "WinBarNC", { link = "StatusLineNC" })

-- Per-window winbar that shows the filename and modified flag
vim.o.winbar = "%{%v:lua.ZephyrusWinbar()%}"
_G.ZephyrusWinbar = function()
  local buf = vim.api.nvim_get_current_buf()
  local bt  = vim.bo[buf].buftype
  local ft  = vim.bo[buf].filetype

  -- skip special windows/sidebars/terminals
  if bt ~= "" or ft == "NvimTree" or ft == "neo-tree" or ft == "aerial"
      or ft == "toggleterm" or ft == "help" or ft == "qf" then
    return ""
  end

  local name = vim.fn.expand("%:~:.")
  if name == "" then name = "[No Name]" end
  local mod = vim.bo[buf].modified and " [+]" or ""
  return "  " .. name .. mod
end

local has_icons, icons = pcall(require, "nvim-web-devicons")
if has_icons then
  _G.ZephyrusWinbar = function()
    local buf = vim.api.nvim_get_current_buf()
    local bt, ft = vim.bo[buf].buftype, vim.bo[buf].filetype
    if bt ~= "" or ft == "NvimTree" or ft == "neo-tree" or ft == "aerial"
        or ft == "toggleterm" or ft == "help" or ft == "qf" then
      return ""
    end
    local fname = vim.fn.expand("%:t")
    local fpath = vim.fn.expand("%:~:.")
    local icon, hl = icons.get_icon(fname, nil, { default = true })
    local mod = vim.bo[buf].modified and " [+]" or ""
    return string.format("  %s %s%s", icon, fpath, mod)
  end
end

vim.opt.showtabline = 1

-- Tooltips for dayssss
-- 🚩 Make tooltips feel snappy (used by CursorHold)
vim.o.updatetime = 250

-- 🩺 Diagnostics look & behavior
vim.diagnostic.config({
  virtual_text = false, -- no inline clutter; use tooltip instead
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "rounded",
    source = "if_many",
    header = "",
    prefix = "",
  },
})

-- 🫧 Show a tooltip when you pause the cursor on a squiggle
-- (only if something is actually under the cursor)
local diag_popup_augroup = vim.api.nvim_create_augroup("ZephyrusDiagTooltip", { clear = true })
vim.api.nvim_create_autocmd({ "CursorHold" }, {
  group = diag_popup_augroup,
  callback = function()
    -- Only open if we have diagnostics right here
    local diags = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
    if #diags > 0 then
      vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" })
    end
  end,
})

-- 🧠 “Cmd+.” → Code Action (like VS Code)
-- Mac Command key is <D-…> in Neovim.
vim.keymap.set({ "n", "v" }, "<D-.>", vim.lsp.buf.code_action, { desc = "Code Action (VSCode-style)" })

-- 🪄 Quick helpers
vim.keymap.set("n", "gl", function() -- “gl” = show diagnostic tooltip on demand
  vim.diagnostic.open_float(nil, { focus = true, scope = "cursor" })
end, { desc = "Line diagnostics (tooltip)" })

vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Prev diagnostic" })

-- 📝 Smarter K: prefer LSP hover, fall back to diagnostic tooltip if no hover
vim.keymap.set("n", "K", function()
  local ok = pcall(vim.lsp.buf.hover)
  if not ok then vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" }) end
end, { desc = "Hover (fallback to diagnostics)" })
