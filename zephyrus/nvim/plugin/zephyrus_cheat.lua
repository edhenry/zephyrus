-- Zephyrus Cheat Sheet popup
-- :ZephyrusCheat  or  <leader>ch

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function cheat_text()
  local base = vim.fn.expand("~/.config/zephyrus/cheatsheets")
  local dark = base .. "/cheetsheet_dark.md"
  local light = base .. "/cheatsheet_light.md"
  local src = (vim.o.background == "light") and light or dark
  local s = read_file(src)
  if s then return s end

  local plugin = debug.getinfo(1, "S").source:sub(2)
  local root = plugin:gsub("/nvim/plugin/.*$", "")
  s = read_file(root .. "/cheatsheets/cheatsheet_dark.md")
  return s or "# Zephyrus Cheat Sheet\n(config not found)"
end

local function open_float(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.8)
  local height = math.floor(ui.height * 0.8)
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = row,
    col = col,
  })

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })

  vim.bo[buf].filetype = "markdown"
  vim.wo[win].wrap = true
end

local function open()
  local txt = cheat_text()
  local lines = {}
  for line in (txt .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  open_float(lines)
end

vim.api.nvim_create_user_command("ZephyrusCheat", open, {})
vim.keymap.set("n", "<leader>ch", open, { desc = "Zephyrus Cheat Sheet" })

return {}
