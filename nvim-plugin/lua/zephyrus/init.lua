--- Zephyrus Command Center - Neovim Plugin
--- Connects to the zephd FastAPI daemon to manage tasks, agents, and reviews.

local ui = require("zephyrus.ui")
local dashboard = require("zephyrus.dashboard")

local M = {}

-- Default configuration
M.config = {
  daemon_url      = "http://127.0.0.1:9800",
  auto_refresh    = false,
  refresh_interval = 5000,  -- ms
  keymaps         = true,
}

-- Status cache for status_line()
local _status_cache = {
  value = "",
  last_fetched = 0,
  ttl = 5,  -- seconds
}

-- Active floating window references (for refresh)
local _active_task_board = nil
local _active_agent_panel = nil

-- ============================================================
-- HTTP helper
-- ============================================================

--- Make an HTTP request to the daemon via curl.
---@param method string HTTP method (GET, POST, PATCH, DELETE)
---@param path string URL path (e.g., "/tasks")
---@param body table|nil Optional request body (will be JSON-encoded)
---@return table|nil data Decoded JSON response, or nil on error
---@return string|nil err Error message if the request failed
local function _request(method, path, body)
  local url = M.config.daemon_url .. path
  local cmd
  if body then
    local json_body = vim.fn.json_encode(body)
    -- Escape single quotes in the JSON body for shell safety
    json_body = json_body:gsub("'", "'\\''")
    cmd = string.format(
      "curl -s -X %s -H 'Content-Type: application/json' -d '%s' '%s'",
      method, json_body, url
    )
  else
    cmd = string.format("curl -s -X %s '%s'", method, url)
  end

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "Connection failed: is zephd running?"
  end

  if result == nil or result == "" then
    return nil, "Empty response"
  end

  local ok, decoded = pcall(vim.fn.json_decode, result)
  if not ok then
    return nil, "Invalid JSON response"
  end

  return decoded
end

-- ============================================================
-- Setup
-- ============================================================

--- Configure the plugin.
---@param opts table|nil Configuration overrides
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Set up highlight groups
  ui.setup_highlights()

  -- Inject the request function into the dashboard module
  dashboard.set_request_fn(_request)

  -- Set up default keymaps under <leader>z
  if M.config.keymaps then
    local map = vim.keymap.set
    map("n", "<leader>zt", function() M.task_board() end,  { desc = "Zephyrus: Task Board" })
    map("n", "<leader>za", function() M.agent_panel() end, { desc = "Zephyrus: Agent Panel" })
    map("n", "<leader>zd", function() M.dashboard() end,   { desc = "Zephyrus: Agent Dashboard" })
    map("n", "<leader>zn", function() M.push_task() end,   { desc = "Zephyrus: New Task" })
    map("n", "<leader>zs", function()
      local s = M.status_line()
      if s ~= "" then
        vim.notify("Zephyrus: " .. s, vim.log.levels.INFO)
      else
        vim.notify("Zephyrus: daemon unreachable", vim.log.levels.WARN)
      end
    end, { desc = "Zephyrus: Show Status" })
  end

  -- Auto-refresh timer
  if M.config.auto_refresh and M.config.refresh_interval > 0 then
    local timer = vim.loop.new_timer()
    timer:start(M.config.refresh_interval, M.config.refresh_interval, vim.schedule_wrap(function()
      M.refresh()
    end))
  end
end

-- ============================================================
-- Task Board
-- ============================================================

--- Get the task ID from the current cursor line in a task board buffer.
---@param buf number Buffer handle
---@return string|nil task_id The extracted task ID, or nil
local function _get_task_id_at_cursor(buf)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_idx = cursor[1]  -- 1-indexed
  -- Skip header (line 1) and separator (line 2)
  if line_idx <= 2 then
    return nil
  end

  local line = vim.api.nvim_buf_get_lines(buf, line_idx - 1, line_idx, false)[1]
  if not line then
    return nil
  end

  -- Extract the ID field: after the status icon, IDs are at a known position
  -- Line format: "  <icon>  <id>  ..."
  -- Find the first contiguous non-space token after the icon
  local id = line:match("^%s+.-%s+(%S+)")
  if id and #id >= 8 then
    return id
  end

  return nil
end

--- Fetch all tasks and look up the full ID by prefix.
---@param prefix string Short task ID prefix
---@return string|nil full_id The full task ID, or nil
local function _resolve_task_id(prefix)
  local tasks, err = _request("GET", "/tasks")
  if not tasks then
    return nil
  end
  for _, task in ipairs(tasks) do
    if task.id and task.id:sub(1, #prefix) == prefix then
      return task.id
    end
  end
  return prefix  -- fall back to using it as-is
end

--- Open a floating window showing all tasks.
function M.task_board()
  local tasks, err = _request("GET", "/tasks")
  if not tasks then
    vim.notify("Zephyrus: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local float = ui.create_float("Zephyrus Task Board", 0.80, 0.70)
  if float.buf == -1 then return end

  _active_task_board = float

  ui.render_tasks(float.buf, tasks)

  -- Buffer-local keymaps
  local buf = float.buf

  -- Refresh
  vim.keymap.set("n", "r", function()
    local new_tasks, new_err = _request("GET", "/tasks")
    if new_tasks then
      ui.render_tasks(buf, new_tasks)
    else
      vim.notify("Zephyrus: " .. (new_err or "refresh failed"), vim.log.levels.ERROR)
    end
  end, { buffer = buf, nowait = true, silent = true })

  -- New task
  vim.keymap.set("n", "n", function()
    M.push_task()
  end, { buffer = buf, nowait = true, silent = true })

  -- Enter: show task detail
  vim.keymap.set("n", "<CR>", function()
    local task_id = _get_task_id_at_cursor(buf)
    if not task_id then
      vim.notify("Zephyrus: no task under cursor", vim.log.levels.WARN)
      return
    end
    local full_id = _resolve_task_id(task_id)
    if not full_id then return end

    local task, task_err = _request("GET", "/tasks/" .. full_id)
    if not task then
      vim.notify("Zephyrus: " .. (task_err or "not found"), vim.log.levels.ERROR)
      return
    end

    local detail_float = ui.create_float("Task: " .. (task.title or task_id):sub(1, 40), 0.60, 0.50)
    if detail_float.buf == -1 then return end

    ui.render_task_detail(detail_float.buf, task)

    -- Detail-level keymaps
    vim.keymap.set("n", "d", function()
      M._complete_task(full_id)
    end, { buffer = detail_float.buf, nowait = true, silent = true })

    vim.keymap.set("n", "m", function()
      M.merge_task(full_id)
    end, { buffer = detail_float.buf, nowait = true, silent = true })

    vim.keymap.set("n", "x", function()
      M.reject_task(full_id)
    end, { buffer = detail_float.buf, nowait = true, silent = true })

    vim.keymap.set("n", "D", function()
      M.review_diff(full_id)
    end, { buffer = detail_float.buf, nowait = true, silent = true })
  end, { buffer = buf, nowait = true, silent = true })

  -- Mark done
  vim.keymap.set("n", "d", function()
    local task_id = _get_task_id_at_cursor(buf)
    if not task_id then return end
    local full_id = _resolve_task_id(task_id)
    if full_id then M._complete_task(full_id) end
  end, { buffer = buf, nowait = true, silent = true })

  -- Merge
  vim.keymap.set("n", "m", function()
    local task_id = _get_task_id_at_cursor(buf)
    if not task_id then return end
    local full_id = _resolve_task_id(task_id)
    if full_id then M.merge_task(full_id) end
  end, { buffer = buf, nowait = true, silent = true })

  -- Reject
  vim.keymap.set("n", "x", function()
    local task_id = _get_task_id_at_cursor(buf)
    if not task_id then return end
    local full_id = _resolve_task_id(task_id)
    if full_id then M.reject_task(full_id) end
  end, { buffer = buf, nowait = true, silent = true })
end

-- ============================================================
-- Agent Panel
-- ============================================================

--- Open a floating window showing all agents.
function M.agent_panel()
  local agents_list, err = _request("GET", "/agents")
  if not agents_list then
    vim.notify("Zephyrus: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local float = ui.create_float("Zephyrus Agent Panel", 0.75, 0.50)
  if float.buf == -1 then return end

  _active_agent_panel = float

  ui.render_agents(float.buf, agents_list)

  -- Refresh keymap
  vim.keymap.set("n", "r", function()
    local new_agents, new_err = _request("GET", "/agents")
    if new_agents then
      ui.render_agents(float.buf, new_agents)
    else
      vim.notify("Zephyrus: " .. (new_err or "refresh failed"), vim.log.levels.ERROR)
    end
  end, { buffer = float.buf, nowait = true, silent = true })
end

-- ============================================================
-- Agent Dashboard (interactive)
-- ============================================================

--- Open the interactive agent dashboard with agent cards.
function M.dashboard()
  -- Ensure request function is injected (in case setup() hasn't run yet)
  dashboard.set_request_fn(_request)
  dashboard.open()
end

-- ============================================================
-- Status Line
-- ============================================================

--- Return a compact string for statusline integration.
--- Caches the result for 5 seconds to avoid excessive API calls.
---@return string status Formatted status string, or "" if unreachable
function M.status_line()
  local now = os.time()
  if (now - _status_cache.last_fetched) < _status_cache.ttl then
    return _status_cache.value
  end

  local data, err = _request("GET", "/status")
  if not data then
    _status_cache.value = ""
    _status_cache.last_fetched = now
    return ""
  end

  local agents_info = data.agents or {}
  local tasks_info  = data.tasks or {}

  local working = agents_info.working or 0
  local total_agents = agents_info.total or 0
  local pending = tasks_info.pending or 0
  local in_review = tasks_info.in_review or 0

  local status_str = string.format(
    " %dw/%da %dp/%dr",
    working, total_agents, pending, in_review
  )

  _status_cache.value = status_str
  _status_cache.last_fetched = now
  return status_str
end

-- ============================================================
-- Push Task
-- ============================================================

--- Prompt the user for a title and description, then create a new task.
function M.push_task()
  vim.ui.input({ prompt = "Task title: " }, function(title)
    if not title or title == "" then
      vim.notify("Zephyrus: task creation cancelled", vim.log.levels.INFO)
      return
    end

    vim.ui.input({ prompt = "Description (optional): " }, function(description)
      local body = {
        title       = title,
        description = description or "",
        priority    = 5,
        created_by  = "nvim",
      }

      local result, err = _request("POST", "/tasks", body)
      if result then
        vim.notify(
          string.format("Zephyrus: task created [%s] %s", (result.id or ""):sub(1, 12), title),
          vim.log.levels.INFO
        )
        -- Auto-refresh the task board if open
        M.refresh()
      else
        vim.notify("Zephyrus: " .. (err or "failed to create task"), vim.log.levels.ERROR)
      end
    end)
  end)
end

-- ============================================================
-- Review Diff
-- ============================================================

--- Show the diff summary for a task in a floating window.
---@param task_id string Task ID (full or prefix)
function M.review_diff(task_id)
  if not task_id or task_id == "" then
    vim.ui.input({ prompt = "Task ID: " }, function(id)
      if id and id ~= "" then
        M.review_diff(id)
      end
    end)
    return
  end

  local diff, err = _request("GET", "/tasks/" .. task_id .. "/diff?project_path=.")
  if not diff then
    vim.notify("Zephyrus: " .. (err or "failed to get diff"), vim.log.levels.ERROR)
    return
  end

  local float = ui.create_float("Diff: " .. task_id:sub(1, 12), 0.70, 0.60)
  if float.buf == -1 then return end

  ui.render_diff(float.buf, diff)
end

-- ============================================================
-- Merge Task
-- ============================================================

--- Merge a task's branch into main.
---@param task_id string Task ID (full or prefix)
function M.merge_task(task_id)
  if not task_id or task_id == "" then
    vim.ui.input({ prompt = "Task ID to merge: " }, function(id)
      if id and id ~= "" then
        M.merge_task(id)
      end
    end)
    return
  end

  -- Confirm before merging
  vim.ui.input({ prompt = string.format("Merge task %s into main? (y/N): ", task_id:sub(1, 12)) }, function(confirm)
    if confirm ~= "y" and confirm ~= "Y" then
      vim.notify("Zephyrus: merge cancelled", vim.log.levels.INFO)
      return
    end

    local result, err = _request("POST", "/tasks/" .. task_id .. "/merge?project_path=.&target=main")
    if result then
      local msg = result.message or "merged successfully"
      vim.notify("Zephyrus: " .. msg, vim.log.levels.INFO)
      M.refresh()
    else
      vim.notify("Zephyrus: " .. (err or "merge failed"), vim.log.levels.ERROR)
    end
  end)
end

-- ============================================================
-- Reject Task
-- ============================================================

--- Prompt for a reason and reject a task.
---@param task_id string Task ID (full or prefix)
function M.reject_task(task_id)
  if not task_id or task_id == "" then
    vim.ui.input({ prompt = "Task ID to reject: " }, function(id)
      if id and id ~= "" then
        M.reject_task(id)
      end
    end)
    return
  end

  vim.ui.input({ prompt = "Rejection reason: " }, function(reason)
    if not reason or reason == "" then
      vim.notify("Zephyrus: rejection cancelled (no reason given)", vim.log.levels.INFO)
      return
    end

    local result, err = _request("POST", "/tasks/" .. task_id .. "/reject", { reason = reason })
    if result then
      vim.notify(
        string.format("Zephyrus: task %s rejected", task_id:sub(1, 12)),
        vim.log.levels.INFO
      )
      M.refresh()
    else
      vim.notify("Zephyrus: " .. (err or "rejection failed"), vim.log.levels.ERROR)
    end
  end)
end

-- ============================================================
-- Complete Task (internal helper)
-- ============================================================

--- Mark a task as complete.
---@param task_id string Full task ID
function M._complete_task(task_id)
  local result, err = _request("POST", "/tasks/" .. task_id .. "/complete")
  if result then
    vim.notify(
      string.format("Zephyrus: task %s marked done", task_id:sub(1, 12)),
      vim.log.levels.INFO
    )
    M.refresh()
  else
    vim.notify("Zephyrus: " .. (err or "failed to complete task"), vim.log.levels.ERROR)
  end
end

-- ============================================================
-- Refresh
-- ============================================================

--- Refresh any open Zephyrus floating windows with fresh data.
function M.refresh()
  -- Refresh task board if open
  if _active_task_board
    and _active_task_board.buf
    and vim.api.nvim_buf_is_valid(_active_task_board.buf) then
    local tasks, _ = _request("GET", "/tasks")
    if tasks then
      ui.render_tasks(_active_task_board.buf, tasks)
    end
  else
    _active_task_board = nil
  end

  -- Refresh agent panel if open
  if _active_agent_panel
    and _active_agent_panel.buf
    and vim.api.nvim_buf_is_valid(_active_agent_panel.buf) then
    local agents_list, _ = _request("GET", "/agents")
    if agents_list then
      ui.render_agents(_active_agent_panel.buf, agents_list)
    end
  else
    _active_agent_panel = nil
  end

  -- Refresh agent dashboard if open
  dashboard.refresh()

  -- Invalidate status cache so next status_line() call fetches fresh data
  _status_cache.last_fetched = 0
end

return M
