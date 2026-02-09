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

  -- Dashboard-specific
  hl(0, "ZephCardSelected", { fg = "#c0caf5", bg = "#292e42", bold = true })
  hl(0, "ZephCardNormal",   { fg = "#a9b1d6" })
  hl(0, "ZephCardLabel",    { fg = "#565f89" })
  hl(0, "ZephCardValue",    { fg = "#c0caf5" })
  hl(0, "ZephCardMode",     { fg = "#73daca", bold = true })
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

--- Render the interactive agent dashboard with agent cards.
---@param buf number Buffer handle
---@param agents_list table[] List of enriched agent objects
---@param selected_idx number 1-indexed selected agent
function M.render_dashboard(buf, agents_list, selected_idx)
  local lines = {}
  local highlights = {}

  -- Title
  table.insert(lines, "  Zephyrus Agent Dashboard")
  table.insert(highlights, { line = 0, col_start = 0, col_end = 28, hl = "ZephTitle" })
  table.insert(lines, "  " .. string.rep("=", 72))
  table.insert(lines, "")

  if #agents_list == 0 then
    table.insert(lines, "  No agents registered.")
    table.insert(lines, "")
    table.insert(lines, "  Start agents with :ZephUp or `zeph up`")
    table.insert(lines, "")
  end

  for i, agent in ipairs(agents_list) do
    local is_selected = (i == selected_idx)
    local marker = is_selected and " >> " or "    "

    -- Agent status icon
    local st = agent.status or "unknown"
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

    local card_start = #lines

    -- Card top border
    local border_hl = is_selected and "ZephCardSelected" or "ZephBorder"
    table.insert(lines, marker .. string.rep("-", 68))
    table.insert(highlights, { line = card_start, col_start = 0, col_end = 72, hl = border_hl })

    -- Line 1: Name + Mode + Status
    local name_str = (agent.name or agent.id:sub(1, 12))
    local mode_str = (agent.mode or "unknown"):upper()
    local status_line_str = string.format(
      "%s| %s  %s [%s]  %s %s",
      marker, st_icon, name_str, mode_str, st_icon, st
    )
    table.insert(lines, status_line_str)
    local line1 = card_start + 1
    table.insert(highlights, { line = line1, col_start = 0, col_end = 4, hl = is_selected and "ZephCardSelected" or "ZephCardNormal" })
    -- Highlight mode tag
    local mode_start = status_line_str:find("%[")
    local mode_end = status_line_str:find("%]")
    if mode_start and mode_end then
      table.insert(highlights, { line = line1, col_start = mode_start - 1, col_end = mode_end, hl = "ZephCardMode" })
    end
    -- Highlight status
    table.insert(highlights, { line = line1, col_start = #status_line_str - #st - 4, col_end = #status_line_str, hl = agent_status_hl(st) })

    -- Line 2: ID + Pane
    local id_str = string.format("%s|   ID: %-26s  Pane: %s", marker, agent.id or "n/a", agent.tmux_pane or "-")
    table.insert(lines, id_str)
    local line2 = card_start + 2
    table.insert(highlights, { line = line2, col_start = 6, col_end = 10, hl = "ZephCardLabel" })
    table.insert(highlights, { line = line2, col_start = 10, col_end = 38, hl = "ZephId" })

    -- Line 3: Current task
    local task_title = agent._task_title or "-"
    local task_status = agent._task_status or ""
    local task_line_str
    if agent.current_task then
      task_line_str = string.format(
        "%s|   Task: [%s] %s (%s)",
        marker, (agent.current_task):sub(1, 12), task_title:sub(1, 35), task_status
      )
    else
      task_line_str = string.format("%s|   Task: none", marker)
    end
    table.insert(lines, task_line_str)
    local line3 = card_start + 3
    table.insert(highlights, { line = line3, col_start = 6, col_end = 12, hl = "ZephCardLabel" })
    if agent.current_task then
      table.insert(highlights, { line = line3, col_start = 13, col_end = 27, hl = "ZephId" })
      -- Highlight task status in parens
      if task_status ~= "" then
        table.insert(highlights, { line = line3, col_start = #task_line_str - #task_status - 1, col_end = #task_line_str - 1, hl = status_hl(task_status) })
      end
    end

    -- Line 4: Branch + Worktree
    local branch_str = agent._task_branch or "-"
    local wt_str = agent.worktree or "-"
    if #wt_str > 35 then
      wt_str = "..." .. wt_str:sub(-32)
    end
    local branch_line = string.format("%s|   Branch: %-30s  Worktree: %s", marker, branch_str:sub(1, 30), wt_str)
    table.insert(lines, branch_line)
    local line4 = card_start + 4
    table.insert(highlights, { line = line4, col_start = 6, col_end = 14, hl = "ZephCardLabel" })
    table.insert(highlights, { line = line4, col_start = 14, col_end = 44, hl = "ZephAgent" })

    -- Line 5: Last seen
    local last_seen = agent.last_seen or "unknown"
    local heartbeat_line = string.format("%s|   Last heartbeat: %s", marker, last_seen)
    table.insert(lines, heartbeat_line)
    local line5 = card_start + 5
    table.insert(highlights, { line = line5, col_start = 6, col_end = 22, hl = "ZephCardLabel" })

    -- Card bottom border
    table.insert(lines, marker .. string.rep("-", 68))
    table.insert(highlights, { line = card_start + 6, col_start = 0, col_end = 72, hl = border_hl })

    -- Spacing between cards
    table.insert(lines, "")
  end

  -- Footer with keybindings
  table.insert(lines, "")
  local footer_line = #lines
  table.insert(lines, " Keys: [j/k] navigate  [Enter] focus pane  [i]nstruct  [d]iff  [m]erge  [x] reject")
  table.insert(lines, "       [a]ssign task   [p]ause/resume      [r]efresh   [q]uit")
  table.insert(highlights, { line = footer_line, col_start = 0, col_end = 82, hl = "ZephHeader" })
  table.insert(highlights, { line = footer_line + 1, col_start = 0, col_end = 64, hl = "ZephHeader" })

  -- Write to buffer
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "zephyrus"

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("zephyrus_dashboard")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, h.hl, h.line, h.col_start, h.col_end)
  end
end

return M
