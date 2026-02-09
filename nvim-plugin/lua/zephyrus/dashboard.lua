--- Zephyrus Command Center - Interactive Agent Dashboard
--- Provides a rich Neovim UI for monitoring and interacting with agents.

local ui = require("zephyrus.ui")

local M = {}

--- Safely convert a value that may be vim.NIL (JSON null) to a Lua string or nil.
local function safe_str(v)
  if v == nil or v == vim.NIL then return nil end
  return tostring(v)
end

-- Module-level state
local _dashboard_state = {
  float = nil,        -- {buf, win}
  agents = {},        -- cached agent list
  selected = 1,       -- 1-indexed selected agent (within agent lines)
  request_fn = nil,   -- HTTP request function (injected from init.lua)
  auto_timer = nil,   -- auto-refresh timer handle
}

--- Inject the HTTP request function from init.lua.
---@param fn function The _request(method, path, body) function
function M.set_request_fn(fn)
  _dashboard_state.request_fn = fn
end

--- Convenience wrapper for HTTP requests.
local function _req(method, path, body)
  if not _dashboard_state.request_fn then
    return nil, "Dashboard not initialized"
  end
  return _dashboard_state.request_fn(method, path, body)
end

-- ============================================================
-- Data fetching
-- ============================================================

--- Fetch full agent data enriched with task info.
---@return table[] agents List of enriched agent objects
local function _fetch_agents()
  local agents_list, err = _req("GET", "/agents")
  if not agents_list then
    return {}, err
  end

  -- Fetch all tasks once to look up current task details
  local tasks, _ = _req("GET", "/tasks")
  local task_map = {}
  if tasks then
    for _, t in ipairs(tasks) do
      task_map[t.id] = t
    end
  end

  -- Enrich agents with task details
  for _, agent in ipairs(agents_list) do
    local ct = safe_str(agent.current_task)
    if ct and task_map[ct] then
      local t = task_map[ct]
      agent._task_title = t.title or ""
      agent._task_status = t.status or ""
      agent._task_branch = safe_str(t.branch) or ""
    end
  end

  return agents_list
end

-- ============================================================
-- Agent card rendering
-- ============================================================

--- Get the currently selected agent.
---@return table|nil agent
local function _selected_agent()
  if #_dashboard_state.agents == 0 then
    return nil
  end
  local idx = _dashboard_state.selected
  if idx < 1 then idx = 1 end
  if idx > #_dashboard_state.agents then idx = #_dashboard_state.agents end
  _dashboard_state.selected = idx
  return _dashboard_state.agents[idx]
end

--- Render the dashboard into the buffer.
local function _render()
  local buf = _dashboard_state.float and _dashboard_state.float.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local agents_list = _dashboard_state.agents
  local selected_idx = _dashboard_state.selected

  ui.render_dashboard(buf, agents_list, selected_idx)
end

--- Refresh data from the daemon and re-render.
local function _refresh()
  local agents_list, err = _fetch_agents()
  if err and #_dashboard_state.agents == 0 then
    vim.notify("Zephyrus Dashboard: " .. err, vim.log.levels.ERROR)
    return
  end
  _dashboard_state.agents = agents_list
  -- Clamp selection
  if _dashboard_state.selected > #agents_list then
    _dashboard_state.selected = math.max(1, #agents_list)
  end
  _render()
end

-- ============================================================
-- Actions
-- ============================================================

--- Focus the selected agent's tmux pane.
local function _action_focus_pane()
  local agent = _selected_agent()
  local pane = safe_str(agent.tmux_pane)
  if not agent or not pane then
    vim.notify("Zephyrus: no tmux pane for this agent", vim.log.levels.WARN)
    return
  end
  vim.fn.system(string.format("tmux select-pane -t %s", pane))
  vim.notify(string.format("Zephyrus: focused pane %s (%s)", pane, safe_str(agent.name) or ""), vim.log.levels.INFO)
end

--- Send an instruction to the selected agent's tmux pane.
local function _action_send_instruction()
  local agent = _selected_agent()
  if not agent then
    vim.notify("Zephyrus: no agent selected", vim.log.levels.WARN)
    return
  end

  local agent_label = safe_str(agent.name) or (safe_str(agent.id) or "?"):sub(1, 12)
  vim.ui.input({ prompt = string.format("Instruction for %s: ", agent_label) }, function(text)
    if not text or text == "" then
      return
    end
    local result, err = _req("POST", "/agents/" .. agent.id .. "/send", { text = text })
    if result then
      vim.notify(
        string.format("Zephyrus: sent to %s: %s", agent_label, text:sub(1, 40)),
        vim.log.levels.INFO
      )
    else
      vim.notify("Zephyrus: " .. (err or "failed to send"), vim.log.levels.ERROR)
    end
  end)
end

--- Show diff for the selected agent's current task.
local function _action_show_diff()
  local agent = _selected_agent()
  local ct = safe_str(agent.current_task)
  if not agent or not ct then
    vim.notify("Zephyrus: agent has no current task", vim.log.levels.WARN)
    return
  end

  local diff, err = _req("GET", "/tasks/" .. ct .. "/diff?project_path=.")
  if not diff then
    vim.notify("Zephyrus: " .. (err or "failed to get diff"), vim.log.levels.ERROR)
    return
  end

  local agent_label = safe_str(agent.name) or (safe_str(agent.id) or "?"):sub(1, 12)
  local float = ui.create_float("Diff: " .. agent_label, 0.70, 0.60)
  if float.buf == -1 then return end
  ui.render_diff(float.buf, diff)
end

--- Merge the selected agent's current task.
local function _action_merge()
  local agent = _selected_agent()
  local task_id = agent and safe_str(agent.current_task)
  if not agent or not task_id then
    vim.notify("Zephyrus: agent has no current task", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = string.format("Merge task %s? (y/N): ", task_id:sub(1, 12)) }, function(confirm)
    if confirm ~= "y" and confirm ~= "Y" then
      vim.notify("Zephyrus: merge cancelled", vim.log.levels.INFO)
      return
    end

    local result, err = _req("POST", "/tasks/" .. task_id .. "/merge?project_path=.&target=main")
    if result then
      vim.notify("Zephyrus: " .. (result.message or "merged"), vim.log.levels.INFO)
      _refresh()
    else
      vim.notify("Zephyrus: " .. (err or "merge failed"), vim.log.levels.ERROR)
    end
  end)
end

--- Reject the selected agent's current task.
local function _action_reject()
  local agent = _selected_agent()
  local task_id = agent and safe_str(agent.current_task)
  if not agent or not task_id then
    vim.notify("Zephyrus: agent has no current task", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "Rejection reason: " }, function(reason)
    if not reason or reason == "" then
      vim.notify("Zephyrus: rejection cancelled", vim.log.levels.INFO)
      return
    end

    local result, err = _req("POST", "/tasks/" .. task_id .. "/reject", { reason = reason })
    if result then
      vim.notify(string.format("Zephyrus: task %s rejected", task_id:sub(1, 12)), vim.log.levels.INFO)
      _refresh()
    else
      vim.notify("Zephyrus: " .. (err or "rejection failed"), vim.log.levels.ERROR)
    end
  end)
end

--- Assign the next available task to the selected agent.
local function _action_assign()
  local agent = _selected_agent()
  if not agent then
    vim.notify("Zephyrus: no agent selected", vim.log.levels.WARN)
    return
  end

  local result, err = _req("POST", "/agents/" .. agent.id .. "/assign")
  if result then
    vim.notify(
      string.format("Zephyrus: assigned task %s to %s", (result.task_id or ""):sub(1, 12), safe_str(agent.name) or ""),
      vim.log.levels.INFO
    )
    _refresh()
  else
    vim.notify("Zephyrus: " .. (err or "no tasks available"), vim.log.levels.ERROR)
  end
end

--- Pause/resume the selected agent.
local function _action_pause()
  local agent = _selected_agent()
  if not agent then
    vim.notify("Zephyrus: no agent selected", vim.log.levels.WARN)
    return
  end

  local result, err = _req("POST", "/agents/" .. agent.id .. "/pause")
  if result then
    vim.notify(
      string.format("Zephyrus: agent %s → %s", safe_str(agent.name) or (safe_str(agent.id) or "?"):sub(1, 12), result.status or ""),
      vim.log.levels.INFO
    )
    _refresh()
  else
    vim.notify("Zephyrus: " .. (err or "pause failed"), vim.log.levels.ERROR)
  end
end

--- Navigate selection up.
local function _nav_up()
  if _dashboard_state.selected > 1 then
    _dashboard_state.selected = _dashboard_state.selected - 1
    _render()
  end
end

--- Navigate selection down.
local function _nav_down()
  if _dashboard_state.selected < #_dashboard_state.agents then
    _dashboard_state.selected = _dashboard_state.selected + 1
    _render()
  end
end

-- ============================================================
-- Public API
-- ============================================================

--- Open the interactive agent dashboard.
function M.open()
  -- Stop any existing auto-refresh
  if _dashboard_state.auto_timer then
    _dashboard_state.auto_timer:stop()
    _dashboard_state.auto_timer:close()
    _dashboard_state.auto_timer = nil
  end

  local float = ui.create_float("Zephyrus Agent Dashboard", 0.85, 0.75)
  if float.buf == -1 then return end

  _dashboard_state.float = float
  _dashboard_state.selected = 1

  -- Fetch initial data
  _dashboard_state.agents = _fetch_agents()
  _render()

  local buf = float.buf

  -- Navigation
  vim.keymap.set("n", "j", _nav_down,   { buffer = buf, nowait = true, silent = true, desc = "Next agent" })
  vim.keymap.set("n", "k", _nav_up,     { buffer = buf, nowait = true, silent = true, desc = "Prev agent" })
  vim.keymap.set("n", "<Down>", _nav_down, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Up>",   _nav_up,   { buffer = buf, nowait = true, silent = true })

  -- Actions
  vim.keymap.set("n", "<CR>", _action_focus_pane, { buffer = buf, nowait = true, silent = true, desc = "Focus pane" })
  vim.keymap.set("n", "i", _action_send_instruction, { buffer = buf, nowait = true, silent = true, desc = "Send instruction" })
  vim.keymap.set("n", "d", _action_show_diff, { buffer = buf, nowait = true, silent = true, desc = "Show diff" })
  vim.keymap.set("n", "m", _action_merge, { buffer = buf, nowait = true, silent = true, desc = "Merge task" })
  vim.keymap.set("n", "x", _action_reject, { buffer = buf, nowait = true, silent = true, desc = "Reject task" })
  vim.keymap.set("n", "a", _action_assign, { buffer = buf, nowait = true, silent = true, desc = "Assign task" })
  vim.keymap.set("n", "p", _action_pause, { buffer = buf, nowait = true, silent = true, desc = "Pause/resume" })
  vim.keymap.set("n", "r", _refresh, { buffer = buf, nowait = true, silent = true, desc = "Refresh" })

  -- Auto-refresh every 3 seconds
  local timer = vim.loop.new_timer()
  _dashboard_state.auto_timer = timer
  timer:start(3000, 3000, vim.schedule_wrap(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      timer:stop()
      timer:close()
      _dashboard_state.auto_timer = nil
      return
    end
    local agents_list = _fetch_agents()
    _dashboard_state.agents = agents_list
    if _dashboard_state.selected > #agents_list then
      _dashboard_state.selected = math.max(1, #agents_list)
    end
    _render()
  end))

  -- Clean up timer when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if _dashboard_state.auto_timer then
        _dashboard_state.auto_timer:stop()
        _dashboard_state.auto_timer:close()
        _dashboard_state.auto_timer = nil
      end
      _dashboard_state.float = nil
    end,
  })
end

--- Refresh the dashboard if it's open (called externally).
function M.refresh()
  if _dashboard_state.float
    and _dashboard_state.float.buf
    and vim.api.nvim_buf_is_valid(_dashboard_state.float.buf) then
    _refresh()
    return true
  end
  return false
end

return M
