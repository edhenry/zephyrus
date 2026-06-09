--- Zephyrus Command Center - UI helpers
--- Floating windows, buffer rendering, and highlight groups.

local M = {}

--- Define highlight groups for task and agent statuses.
function M.setup_highlights()
  local hl = vim.api.nvim_set_hl

  -- Task statuses
  hl(0, "ZephPending",    { fg = "#e0af68", bold = true })   -- amber/yellow
  hl(0, "ZephInProgress", { fg = "#7aa2f7", bold = true })   -- blue
  hl(0, "ZephInReview",   { fg = "#bb9af7", bold = true })   -- purple
  hl(0, "ZephDone",       { fg = "#9ece6a", bold = true })   -- green
  hl(0, "ZephFailed",     { fg = "#f7768e", bold = true })   -- red
  hl(0, "ZephBlocked",    { fg = "#565f89", bold = true })   -- gray

  -- Agent statuses
  hl(0, "ZephAgentIdle",    { fg = "#9ece6a" })
  hl(0, "ZephAgentWorking", { fg = "#7aa2f7", bold = true })
  hl(0, "ZephAgentError",   { fg = "#f7768e", bold = true })
  hl(0, "ZephAgentStarting",{ fg = "#e0af68" })

  -- UI chrome
  hl(0, "ZephTitle",      { fg = "#c0caf5", bold = true })
  hl(0, "ZephHeader",     { fg = "#565f89", underline = true })
  hl(0, "ZephBorder",     { fg = "#3b4261" })
  hl(0, "ZephPriority",   { fg = "#ff9e64", bold = true })
  hl(0, "ZephId",         { fg = "#565f89" })
  hl(0, "ZephAgent",      { fg = "#73daca" })

  -- Dashboard cards
  hl(0, "ZephCardSelected", { fg = "#c0caf5", bg = "#292e42", bold = true })
  hl(0, "ZephCardNormal",   { fg = "#a9b1d6" })
  hl(0, "ZephCardLabel",    { fg = "#565f89" })
  hl(0, "ZephCardValue",    { fg = "#c0caf5" })
  hl(0, "ZephCardMode",     { fg = "#73daca", bold = true })
  hl(0, "ZephBoxBorder",    { fg = "#3b4261" })
  hl(0, "ZephBoxBorderSel", { fg = "#7aa2f7" })

  -- Detail view (tmux pane capture)
  hl(0, "ZephThinking",     { fg = "#565f89", italic = true })
  hl(0, "ZephToolCall",     { fg = "#73daca", bold = true })
  hl(0, "ZephToolSuccess",  { fg = "#9ece6a" })
  hl(0, "ZephToolError",    { fg = "#f7768e", bold = true })
  hl(0, "ZephUserInput",    { fg = "#c0caf5", bold = true })
  hl(0, "ZephSeparator",    { fg = "#3b4261" })
  hl(0, "ZephDetailHeader", { fg = "#c0caf5", bg = "#1a1b26", bold = true })
end

--- Create a centered floating window with a border and title.
---@param title string Window title shown in the border
---@param width_pct number Width as a fraction of the editor (0.0-1.0)
---@param height_pct number Height as a fraction of the editor (0.0-1.0)
---@return table {buf: number, win: number}
function M.create_float(title, width_pct, height_pct)
  local ui = vim.api.nvim_list_uis()[1]
  if not ui then
    vim.notify("Zephyrus: no UI attached", vim.log.levels.ERROR)
    return { buf = -1, win = -1 }
  end

  local width  = math.floor(ui.width * width_pct)
  local height = math.floor(ui.height * height_pct)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile  = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style    = "minimal",
    border   = "rounded",
    title    = " " .. title .. " ",
    title_pos = "center",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
  })

  -- Close with q or Esc
  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q",     close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })

  return { buf = buf, win = win }
end

--- Map a task status string to a display icon.
---@param status string
---@return string
local function status_icon(status)
  local icons = {
    pending     = "  ",
    claimed     = "  ",
    in_progress = "  ",
    in_review   = "  ",
    done        = "  ",
    failed      = "  ",
    blocked     = "  ",
  }
  return icons[status] or "  "
end

--- Map a task status string to its highlight group name.
---@param status string
---@return string
local function status_hl(status)
  local map = {
    pending     = "ZephPending",
    claimed     = "ZephInProgress",
    in_progress = "ZephInProgress",
    in_review   = "ZephInReview",
    done        = "ZephDone",
    failed      = "ZephFailed",
    blocked     = "ZephBlocked",
  }
  return map[status] or "Normal"
end

--- Map an agent status string to its highlight group name.
---@param status string
---@return string
local function agent_status_hl(status)
  local map = {
    starting = "ZephAgentStarting",
    idle     = "ZephAgentIdle",
    working  = "ZephAgentWorking",
    waiting  = "ZephAgentWorking",
    done     = "ZephAgentIdle",
    error    = "ZephAgentError",
  }
  return map[status] or "Normal"
end

--- Map a priority integer to a display string.
---@param priority number
---@return string
local function priority_label(priority)
  if priority <= 2 then
    return "P" .. priority .. "!"
  elseif priority <= 4 then
    return "P" .. priority .. " "
  else
    return "P" .. priority .. " "
  end
end

--- Render a list of tasks into a buffer with highlights.
---@param buf number Buffer handle
---@param tasks table[] List of task objects from the API
function M.render_tasks(buf, tasks)
  local lines = {}
  local highlights = {}

  -- Header
  local header = string.format(
    "  %-6s  %-14s  %-4s  %-40s  %-12s  %-16s",
    "STATUS", "ID", "PRI", "TITLE", "STATUS", "AGENT"
  )
  table.insert(lines, header)
  table.insert(highlights, { line = 0, col_start = 0, col_end = #header, hl = "ZephHeader" })
  table.insert(lines, string.rep("-", #header))

  if #tasks == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No tasks found. Press 'n' to create one.")
    table.insert(lines, "")
  end

  for i, task in ipairs(tasks) do
    local icon  = status_icon(task.status or "pending")
    local id    = (task.id or ""):sub(1, 12)
    local pri   = priority_label(task.priority or 5)
    local title = (task.title or ""):sub(1, 40)
    local st    = (task.status or "unknown")
    local agent = (task.assigned_to or "-"):sub(1, 16)

    local line = string.format("  %s  %-14s  %s  %-40s  %-12s  %-16s", icon, id, pri, title, st, agent)
    table.insert(lines, line)

    local line_idx = i + 1  -- account for header + separator line
    -- Highlight the icon/status portion
    table.insert(highlights, { line = line_idx, col_start = 0, col_end = 6, hl = status_hl(task.status or "pending") })
    -- Highlight ID
    table.insert(highlights, { line = line_idx, col_start = 8, col_end = 22, hl = "ZephId" })
    -- Highlight priority
    table.insert(highlights, { line = line_idx, col_start = 24, col_end = 28, hl = "ZephPriority" })
    -- Highlight status label
    table.insert(highlights, { line = line_idx, col_start = 70, col_end = 82, hl = status_hl(task.status or "pending") })
    -- Highlight agent
    table.insert(highlights, { line = line_idx, col_start = 84, col_end = 100, hl = "ZephAgent" })
  end

  -- Footer with keybindings
  table.insert(lines, "")
  table.insert(lines, " Keys: [q]uit  [r]efresh  [n]ew task  [Enter] detail  [d]one  [m]erge  [x] reject")

  -- Write to buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "zephyrus"

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("zephyrus_tasks")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

--- Render a single task's detail view into a buffer.
---@param buf number Buffer handle
---@param task table Task object from the API
function M.render_task_detail(buf, task)
  local lines = {}
  local highlights = {}

  table.insert(lines, "  Task Detail")
  table.insert(highlights, { line = 0, col_start = 0, col_end = 13, hl = "ZephTitle" })
  table.insert(lines, string.rep("-", 60))
  table.insert(lines, "")
  table.insert(lines, "  ID:          " .. (task.id or "n/a"))
  table.insert(lines, "  Title:       " .. (task.title or "n/a"))
  table.insert(lines, "  Status:      " .. status_icon(task.status or "pending") .. " " .. (task.status or "n/a"))
  table.insert(lines, "  Priority:    " .. priority_label(task.priority or 5))
  table.insert(lines, "  Branch:      " .. (task.branch or "n/a"))
  table.insert(lines, "  Assigned to: " .. (task.assigned_to or "none"))
  table.insert(lines, "  Created by:  " .. (task.created_by or "n/a"))
  table.insert(lines, "")

  if task.description and task.description ~= "" then
    table.insert(lines, "  Description:")
    for desc_line in task.description:gmatch("[^\n]+") do
      table.insert(lines, "    " .. desc_line)
    end
    table.insert(lines, "")
  end

  if task.tags and #task.tags > 0 then
    table.insert(lines, "  Tags: " .. table.concat(task.tags, ", "))
    table.insert(lines, "")
  end

  if task.output and task.output ~= "" then
    table.insert(lines, "  Output:")
    for out_line in task.output:gmatch("[^\n]+") do
      table.insert(lines, "    " .. out_line)
    end
    table.insert(lines, "")
  end

  table.insert(lines, " Keys: [q]uit  [d]one  [m]erge  [x] reject  [D]iff")

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "zephyrus"

  local ns = vim.api.nvim_create_namespace("zephyrus_detail")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

--- Render a list of agents into a buffer with highlights.
---@param buf number Buffer handle
---@param agents_list table[] List of agent objects from the API
function M.render_agents(buf, agents_list)
  local lines = {}
  local highlights = {}

  -- Header
  local header = string.format(
    "  %-14s  %-14s  %-10s  %-10s  %-20s  %-12s",
    "ID", "NAME", "MODE", "STATUS", "CURRENT TASK", "TMUX PANE"
  )
  table.insert(lines, header)
  table.insert(highlights, { line = 0, col_start = 0, col_end = #header, hl = "ZephHeader" })
  table.insert(lines, string.rep("-", #header))

  if #agents_list == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No agents registered.")
    table.insert(lines, "")
  end

  for i, agent in ipairs(agents_list) do
    local id        = (agent.id or ""):sub(1, 12)
    local name      = (agent.name or ""):sub(1, 14)
    local mode      = (agent.mode or ""):sub(1, 10)
    local st        = (agent.status or "unknown")
    local task      = (agent.current_task or "-"):sub(1, 20)
    local pane      = (agent.tmux_pane or "-"):sub(1, 12)

    -- Status icons for agents
    local st_icon
    if st == "working" then
      st_icon = " "
    elseif st == "idle" then
      st_icon = " "
    elseif st == "error" then
      st_icon = " "
    elseif st == "starting" then
      st_icon = " "
    else
      st_icon = " "
    end

    local line = string.format(
      "  %-14s  %-14s  %-10s  %s %-8s  %-20s  %-12s",
      id, name, mode, st_icon, st, task, pane
    )
    table.insert(lines, line)

    local line_idx = i + 1
    -- Highlight the status portion
    table.insert(highlights, { line = line_idx, col_start = 42, col_end = 56, hl = agent_status_hl(st) })
    -- Highlight ID
    table.insert(highlights, { line = line_idx, col_start = 2, col_end = 16, hl = "ZephId" })
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, " Keys: [q]uit  [r]efresh")

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "zephyrus"

  local ns = vim.api.nvim_create_namespace("zephyrus_agents")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

--- Render a diff summary into a buffer.
---@param buf number Buffer handle
---@param diff table Diff response from the API
function M.render_diff(buf, diff)
  local lines = {}
  local highlights = {}

  table.insert(lines, "  Diff Summary")
  table.insert(highlights, { line = 0, col_start = 0, col_end = 14, hl = "ZephTitle" })
  table.insert(lines, string.rep("-", 60))
  table.insert(lines, "")
  table.insert(lines, "  Branch:    " .. (diff.branch or "n/a"))
  table.insert(lines, "  Base:      " .. (diff.base or "n/a"))
  table.insert(lines, "  Summary:   " .. (diff.shortstat or "n/a"))
  table.insert(lines, "")

  if diff.stat and diff.stat ~= "" then
    table.insert(lines, "  Stat:")
    for stat_line in diff.stat:gmatch("[^\n]+") do
      table.insert(lines, "    " .. stat_line)
    end
    table.insert(lines, "")
  end

  if diff.files and #diff.files > 0 then
    table.insert(lines, "  Changed files:")
    table.insert(lines, string.format("    %-10s  %s", "STATUS", "PATH"))
    table.insert(lines, "    " .. string.rep("-", 50))
    for _, f in ipairs(diff.files) do
      local file_status = (f.status or "?"):sub(1, 10)
      local file_path   = f.path or ""
      table.insert(lines, string.format("    %-10s  %s", file_status, file_path))
    end
  end

  table.insert(lines, "")
  table.insert(lines, " Keys: [q]uit")

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "zephyrus"

  local ns = vim.api.nvim_create_namespace("zephyrus_diff")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

--- Helper: safely convert a value that may be vim.NIL/null to a Lua string or nil.
---@param v any
---@return string|nil
local function safe_str(v)
  if v == nil or v == vim.NIL then return nil end
  return tostring(v)
end

--- Pad a string with spaces to reach a target display width.
---@param str string
---@param target number Desired display width
---@return string
local function pad_display(str, target)
  local dw = vim.fn.strdisplaywidth(str)
  local padding = math.max(0, target - dw)
  return str .. string.rep(" ", padding)
end

-- ============================================================
-- Dashboard: Task List (left pane)
-- ============================================================

--- Render the task list for the dashboard left pane.
---@param buf number Buffer handle
---@param tasks table[] List of task objects
---@param selected_idx number 1-indexed selected task
---@param is_focused boolean Whether this pane has focus
function M.render_task_list(buf, tasks, selected_idx, is_focused)
  local lines = {}
  local highlights = {}
  local focus_icon = is_focused and "●" or "○"

  -- Header
  table.insert(lines, string.format(" %s Task Stack (%d)", focus_icon, #tasks))
  table.insert(highlights, { line = 0, col_start = 0, col_end = -1, hl = "ZephTitle" })
  table.insert(lines, " " .. string.rep("─", 28))
  table.insert(highlights, { line = 1, col_start = 0, col_end = -1, hl = "ZephSeparator" })
  table.insert(lines, "")

  if #tasks == 0 then
    table.insert(lines, " No tasks.")
    table.insert(lines, " Press N to create one.")
    table.insert(lines, "")
  end

  local task_icons = {
    pending = "○", claimed = "◐", in_progress = "●",
    in_review = "◉", done = "✓", failed = "✗", blocked = "⊘",
  }

  for i, task in ipairs(tasks) do
    local is_sel = (i == selected_idx) and is_focused
    local marker = is_sel and "▸" or " "
    local icon = task_icons[task.status or "pending"] or "?"
    local pri = string.format("P%d", task.priority or 5)
    local title = (task.title or ""):sub(1, 22)

    -- Main line: marker icon [pri] title
    local line = string.format(" %s %s [%s] %s", marker, icon, pri, title)
    table.insert(lines, line)
    local li = #lines - 1

    if is_sel then
      table.insert(highlights, { line = li, col_start = 0, col_end = -1, hl = "ZephCardSelected" })
    end
    -- Icon highlight
    local icon_byte = line:find(icon, 1, true)
    if icon_byte then
      table.insert(highlights, { line = li, col_start = icon_byte - 1, col_end = icon_byte - 1 + #icon, hl = status_hl(task.status or "pending") })
    end
    -- Priority highlight
    local pri_start = line:find("%[P")
    if pri_start then
      table.insert(highlights, { line = li, col_start = pri_start - 1, col_end = pri_start + #pri, hl = "ZephPriority" })
    end

    -- Sub-line: assignee + status
    local assignee_id = safe_str(task.assigned_to)
    local assign_str = assignee_id and ("→ " .. assignee_id:sub(1, 16)) or "unassigned"
    local st = task.status or ""
    local sub_line = string.format("       %s  %s", assign_str, st)
    table.insert(lines, sub_line)
    local sli = #lines - 1
    if assignee_id then
      table.insert(highlights, { line = sli, col_start = 7, col_end = 7 + #assign_str, hl = "ZephAgent" })
    end
    table.insert(highlights, { line = sli, col_start = #sub_line - #st, col_end = #sub_line, hl = status_hl(st) })
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, " " .. string.rep("─", 28))
  table.insert(lines, " N=new task  Tab=switch")
  table.insert(highlights, { line = #lines - 2, col_start = 0, col_end = -1, hl = "ZephSeparator" })
  table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, hl = "ZephHeader" })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("zephyrus_tasklist")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

-- ============================================================
-- Dashboard: Agent Cards (right pane, cards mode)
-- ============================================================

--- Render agent cards for the dashboard right pane.
---@param buf number Buffer handle
---@param agents_list table[] List of enriched agent objects
---@param selected_idx number 1-indexed selected agent
---@param is_focused boolean Whether this pane has focus
---@param width number Available window width
function M.render_agent_cards(buf, agents_list, selected_idx, is_focused, width)
  local lines = {}
  local highlights = {}
  local focus_icon = is_focused and "●" or "○"
  local card_w = math.max(40, width - 4)  -- inner card width

  -- Header
  table.insert(lines, string.format("  %s Agent Cards (%d)", focus_icon, #agents_list))
  table.insert(highlights, { line = 0, col_start = 0, col_end = -1, hl = "ZephTitle" })
  table.insert(lines, "  " .. string.rep("═", card_w))
  table.insert(highlights, { line = 1, col_start = 0, col_end = -1, hl = "ZephSeparator" })
  table.insert(lines, "")

  if #agents_list == 0 then
    table.insert(lines, "  No agents registered.")
    table.insert(lines, "")
    table.insert(lines, "  Start agents with :ZephUp or `zeph up`")
    table.insert(lines, "")
  end

  local agent_icons = {
    working = "●", idle = "○", error = "✗", starting = "◐", waiting = "◑", done = "✓",
  }

  for i, agent in ipairs(agents_list) do
    local is_sel = (i == selected_idx) and is_focused
    local inner_w = card_w - 4  -- 2 for "│ " and " │"

    local st = safe_str(agent.status) or "unknown"
    local name = safe_str(agent.name) or (safe_str(agent.id) or "?"):sub(1, 12)
    local mode = (safe_str(agent.mode) or "?"):upper()
    local st_icon = agent_icons[st] or "?"
    local bdr_hl = is_sel and "ZephBoxBorderSel" or "ZephBoxBorder"

    local card_start = #lines

    -- Top border: ┌─ name ── [MODE] ── ● STATUS ──────┐
    local top_inner = string.format(" %s ── [%s] ── %s %s ", name, mode, st_icon, st)
    local remaining = math.max(0, inner_w - vim.fn.strdisplaywidth(top_inner))
    local top_line = "  ┌─" .. top_inner .. string.rep("─", remaining) .. "─┐"
    table.insert(lines, top_line)
    table.insert(highlights, { line = card_start, col_start = 0, col_end = -1, hl = bdr_hl })
    -- Highlight mode tag
    local ms, me = top_line:find("%[%u+%]")
    if ms then
      table.insert(highlights, { line = card_start, col_start = ms - 1, col_end = me, hl = "ZephCardMode" })
    end
    -- Highlight status
    local ss = top_line:find(st, 1, true)
    if ss then
      table.insert(highlights, { line = card_start, col_start = ss - 1, col_end = ss - 1 + #st, hl = agent_status_hl(st) })
    end

    -- Card content lines
    local function card_line(content)
      local padded = pad_display(content, inner_w)
      local cl = "  │ " .. padded .. " │"
      table.insert(lines, cl)
      local li = #lines - 1
      table.insert(highlights, { line = li, col_start = 0, col_end = 5, hl = bdr_hl })
      table.insert(highlights, { line = li, col_start = #cl - 3, col_end = -1, hl = bdr_hl })
      if is_sel then
        table.insert(highlights, { line = li, col_start = 5, col_end = #cl - 3, hl = "ZephCardSelected" })
      end
      return li
    end

    -- Task line
    local ct = safe_str(agent.current_task)
    local task_title = safe_str(agent._task_title) or "-"
    local task_status = safe_str(agent._task_status) or ""
    if ct then
      local task_str = string.format("Task: [%s] %s (%s)", ct:sub(1, 12), task_title:sub(1, 30), task_status)
      local tl = card_line(task_str)
      -- Highlight task ID
      local tid_s = lines[tl + 1]:find("%[")
      local tid_e = lines[tl + 1]:find("%]")
      if tid_s and tid_e then
        table.insert(highlights, { line = tl, col_start = tid_s - 1, col_end = tid_e, hl = "ZephId" })
      end
      -- Highlight task status
      if task_status ~= "" then
        local ts_s = lines[tl + 1]:find(task_status, 1, true)
        if ts_s then
          table.insert(highlights, { line = tl, col_start = ts_s - 1, col_end = ts_s - 1 + #task_status, hl = status_hl(task_status) })
        end
      end
    else
      card_line("Task: none")
    end

    -- Branch line
    local branch = safe_str(agent._task_branch) or "-"
    card_line(string.format("Branch: %s", branch:sub(1, inner_w - 10)))

    -- Pane + heartbeat line
    local pane = safe_str(agent.tmux_pane) or "-"
    local last_seen = safe_str(agent.last_seen) or "?"
    -- Show just the time portion if it's an ISO timestamp
    local time_part = last_seen:match("T(%d+:%d+:%d+)") or last_seen
    card_line(string.format("Pane: %-18s  Heartbeat: %s", pane, time_part:sub(1, 12)))

    -- Bottom border
    local bottom_line = "  └" .. string.rep("─", inner_w + 2) .. "┘"
    table.insert(lines, bottom_line)
    table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, hl = bdr_hl })

    -- Spacing
    table.insert(lines, "")
  end

  -- Footer
  table.insert(lines, "  " .. string.rep("─", card_w))
  table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, hl = "ZephSeparator" })
  table.insert(lines, "  j/k=navigate  Enter=drill in  i=instruct  d=diff  m=merge  x=reject")
  table.insert(lines, "  a=assign  p=pause  r=refresh  Tab=switch  q=quit")
  table.insert(highlights, { line = #lines - 2, col_start = 0, col_end = -1, hl = "ZephHeader" })
  table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, hl = "ZephHeader" })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("zephyrus_cards")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

-- ============================================================
-- Dashboard: Agent Detail (right pane, detail mode)
-- ============================================================

--- Pattern-based highlight rules for tmux pane capture lines.
local _detail_patterns = {
  { pat = "^%s*Read%s+",    hl = "ZephToolCall" },
  { pat = "^%s*Edit%s+",    hl = "ZephToolCall" },
  { pat = "^%s*Write%s+",   hl = "ZephToolCall" },
  { pat = "^%s*Bash%s+",    hl = "ZephToolCall" },
  { pat = "^%s*Grep%s+",    hl = "ZephToolCall" },
  { pat = "^%s*Glob%s+",    hl = "ZephToolCall" },
  { pat = "^%s*Task%s+",    hl = "ZephToolCall" },
  { pat = "^%s*WebFetch%s+", hl = "ZephToolCall" },
  { pat = "^%s*WebSearch%s+", hl = "ZephToolCall" },
  { pat = "^%s*NotebookEdit%s+", hl = "ZephToolCall" },
  { pat = "✓",              hl = "ZephToolSuccess" },
  { pat = "✗",              hl = "ZephToolError" },
  { pat = "[Ee]rror:",      hl = "ZephToolError" },
  { pat = "[Ff]ailed",      hl = "ZephToolError" },
  { pat = "^%s*>",          hl = "ZephUserInput" },
  { pat = "^%s*%$",         hl = "ZephUserInput" },
  { pat = "[Tt]hinking",    hl = "ZephThinking" },
}

--- Render agent detail view with tmux pane capture.
---@param buf number Buffer handle
---@param agent table Agent object (enriched)
---@param capture_lines string[] Lines captured from tmux pane
---@param width number Available window width
function M.render_agent_detail(buf, agent, capture_lines, width)
  local lines = {}
  local highlights = {}
  local sep_w = math.max(40, width - 4)

  local name = safe_str(agent.name) or (safe_str(agent.id) or "?"):sub(1, 12)
  local mode = (safe_str(agent.mode) or "?"):upper()
  local st = safe_str(agent.status) or "unknown"
  local ct = safe_str(agent.current_task)
  local task_title = safe_str(agent._task_title) or ""
  local task_status = safe_str(agent._task_status) or ""
  local branch = safe_str(agent._task_branch) or "-"
  local pane = safe_str(agent.tmux_pane) or "-"

  local agent_icons = {
    working = "●", idle = "○", error = "✗", starting = "◐", waiting = "◑", done = "✓",
  }
  local st_icon = agent_icons[st] or "?"

  -- Header block
  local h1 = string.format("  ═══ %s [%s] %s %s ", name, mode, st_icon, st)
  h1 = h1 .. string.rep("═", math.max(0, sep_w - vim.fn.strdisplaywidth(h1)))
  table.insert(lines, h1)
  table.insert(highlights, { line = 0, col_start = 0, col_end = -1, hl = "ZephDetailHeader" })
  -- Highlight mode
  local ms, me = h1:find("%[%u+%]")
  if ms then
    table.insert(highlights, { line = 0, col_start = ms - 1, col_end = me, hl = "ZephCardMode" })
  end
  -- Highlight status word
  local sts = h1:find(st, 1, true)
  if sts then
    table.insert(highlights, { line = 0, col_start = sts - 1, col_end = sts - 1 + #st, hl = agent_status_hl(st) })
  end

  -- Info lines
  if ct then
    table.insert(lines, string.format("  Task: [%s] %s (%s)", ct:sub(1, 12), task_title:sub(1, 40), task_status))
  else
    table.insert(lines, "  Task: none")
  end
  table.insert(highlights, { line = 1, col_start = 2, col_end = 7, hl = "ZephCardLabel" })
  if ct and task_status ~= "" then
    local tss = lines[2]:find(task_status, 1, true)
    if tss then
      table.insert(highlights, { line = 1, col_start = tss - 1, col_end = tss - 1 + #task_status, hl = status_hl(task_status) })
    end
  end

  table.insert(lines, string.format("  Branch: %s    Pane: %s", branch:sub(1, 35), pane))
  table.insert(highlights, { line = 2, col_start = 2, col_end = 9, hl = "ZephCardLabel" })

  -- Separator
  table.insert(lines, "  " .. string.rep("─", sep_w))
  table.insert(highlights, { line = 3, col_start = 0, col_end = -1, hl = "ZephSeparator" })
  table.insert(lines, "")

  -- Captured pane content
  local capture_start = #lines
  for _, cline in ipairs(capture_lines) do
    table.insert(lines, "  " .. cline)
  end

  -- Apply pattern-based highlighting to captured lines
  for idx = capture_start, #lines - 1 do
    local text = lines[idx + 1]
    for _, rule in ipairs(_detail_patterns) do
      if text:find(rule.pat) then
        table.insert(highlights, { line = idx, col_start = 0, col_end = -1, hl = rule.hl })
        break  -- first match wins
      end
    end
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, "  " .. string.rep("─", sep_w))
  table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, hl = "ZephSeparator" })
  table.insert(lines, "  i=instruct  d=diff  m=merge  x=reject  Enter=takeover  Esc=back  G=bottom")
  table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, hl = "ZephHeader" })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("zephyrus_detail")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

return M
