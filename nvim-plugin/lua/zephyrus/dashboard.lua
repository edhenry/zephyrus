--- Zephyrus Command Center — Interactive Agent Dashboard
--- Tab-based layout: left = task stack, right = agent cards / agent detail.

local ui = require("zephyrus.ui")

local M = {}

--- Safely convert a value that may be vim.NIL (JSON null) to a Lua string or nil.
local function safe_str(v)
  if v == nil or v == vim.NIL then return nil end
  return tostring(v)
end

-- ============================================================
-- State
-- ============================================================

local _state = {
  tab       = nil,        -- tabpage handle
  task_win  = nil,        -- left pane window
  task_buf  = nil,        -- left pane buffer
  main_win  = nil,        -- right pane window
  main_buf  = nil,        -- right pane buffer
  agents    = {},         -- cached agent list (enriched)
  tasks     = {},         -- cached task list
  mode      = "cards",    -- "cards" | "detail"
  focus     = "agents",   -- "tasks" | "agents"
  sel_agent = 1,          -- 1-indexed selected agent
  sel_task  = 1,          -- 1-indexed selected task
  detail_agent = nil,     -- agent object being viewed in detail
  auto_timer = nil,       -- uv timer handle
  request_fn = nil,       -- HTTP request function (injected from init.lua)
}

--- Inject the HTTP request function from init.lua.
function M.set_request_fn(fn)
  _state.request_fn = fn
end

local function _req(method, path, body)
  if not _state.request_fn then return nil, "not initialized" end
  return _state.request_fn(method, path, body)
end

-- ============================================================
-- Data fetching
-- ============================================================

local function _fetch_tasks()
  local tasks, _ = _req("GET", "/tasks")
  return tasks or {}
end

local function _fetch_agents()
  local agents_list, _ = _req("GET", "/agents")
  if not agents_list then return {} end

  -- Build task lookup from cached tasks
  local task_map = {}
  for _, t in ipairs(_state.tasks) do
    task_map[t.id] = t
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

--- Capture a tmux pane's visible content + scrollback.
---@param pane_target string tmux pane target (e.g. "zephyrus:0.1")
---@return string[] lines
local function _capture_pane(pane_target)
  if not pane_target then
    return { "(no pane assigned)" }
  end
  local lines = vim.fn.systemlist(
    string.format("tmux capture-pane -t %s -p -S -500 2>/dev/null", vim.fn.shellescape(pane_target))
  )
  if vim.v.shell_error ~= 0 then
    return { "(capture failed — pane may not exist)" }
  end
  -- Strip ANSI escape sequences for clean rendering
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("\27%[[%d;]*[a-zA-Z]", "")
  end
  return lines
end

-- ============================================================
-- Helpers
-- ============================================================

local function _selected_agent()
  if #_state.agents == 0 then return nil end
  _state.sel_agent = math.max(1, math.min(_state.sel_agent, #_state.agents))
  return _state.agents[_state.sel_agent]
end

local function _selected_task()
  if #_state.tasks == 0 then return nil end
  _state.sel_task = math.max(1, math.min(_state.sel_task, #_state.tasks))
  return _state.tasks[_state.sel_task]
end

local function _is_open()
  return _state.tab
    and vim.api.nvim_tabpage_is_valid(_state.tab)
    and _state.main_buf and vim.api.nvim_buf_is_valid(_state.main_buf)
    and _state.task_buf and vim.api.nvim_buf_is_valid(_state.task_buf)
end

--- Get the agent relevant for the current context (detail agent or selected card).
local function _active_agent()
  if _state.mode == "detail" and _state.detail_agent then
    return _state.detail_agent
  end
  return _selected_agent()
end

-- ============================================================
-- Rendering
-- ============================================================

local function _render_tasks()
  if not _is_open() then return end
  local is_focused = _state.focus == "tasks"
  ui.render_task_list(_state.task_buf, _state.tasks, _state.sel_task, is_focused)
end

local function _render_main()
  if not _is_open() then return end
  local width = vim.api.nvim_win_get_width(_state.main_win)

  if _state.mode == "detail" and _state.detail_agent then
    local pane = safe_str(_state.detail_agent.tmux_pane)
    local capture_lines = _capture_pane(pane)
    ui.render_agent_detail(_state.main_buf, _state.detail_agent, capture_lines, width)
  else
    local is_focused = _state.focus == "agents"
    ui.render_agent_cards(_state.main_buf, _state.agents, _state.sel_agent, is_focused, width)
  end
end

local function _refresh()
  if not _is_open() then return end

  -- Save cursor in main pane (for detail scroll preservation)
  local main_cursor
  if _state.main_win and vim.api.nvim_win_is_valid(_state.main_win) then
    main_cursor = vim.api.nvim_win_get_cursor(_state.main_win)
  end

  _state.tasks = _fetch_tasks()
  _state.agents = _fetch_agents()

  -- If in detail mode, update the detail agent reference
  if _state.mode == "detail" and _state.detail_agent then
    local aid = _state.detail_agent.id
    local found = false
    for _, a in ipairs(_state.agents) do
      if a.id == aid then
        _state.detail_agent = a
        found = true
        break
      end
    end
    if not found then
      -- Agent disappeared — go back to cards
      _state.mode = "cards"
      _state.detail_agent = nil
      if _state.main_win and vim.api.nvim_win_is_valid(_state.main_win) then
        vim.wo[_state.main_win].wrap = false
      end
    end
  end

  -- Clamp selections
  if _state.sel_agent > #_state.agents then
    _state.sel_agent = math.max(1, #_state.agents)
  end
  if _state.sel_task > #_state.tasks then
    _state.sel_task = math.max(1, #_state.tasks)
  end

  _render_tasks()
  _render_main()

  -- Restore cursor in main pane
  if main_cursor and _state.mode == "detail" and _state.main_win and vim.api.nvim_win_is_valid(_state.main_win) then
    local lc = vim.api.nvim_buf_line_count(_state.main_buf)
    main_cursor[1] = math.min(main_cursor[1], lc)
    pcall(vim.api.nvim_win_set_cursor, _state.main_win, main_cursor)
  end
end

-- ============================================================
-- Navigation
-- ============================================================

local function _task_nav(delta)
  if #_state.tasks == 0 then return end
  _state.sel_task = math.max(1, math.min(_state.sel_task + delta, #_state.tasks))
  _render_tasks()
end

local function _agent_nav(delta)
  if _state.mode == "detail" then
    -- In detail mode, j/k scroll normally
    vim.cmd(delta > 0 and "normal! j" or "normal! k")
    return
  end
  if #_state.agents == 0 then return end
  _state.sel_agent = math.max(1, math.min(_state.sel_agent + delta, #_state.agents))
  _render_main()
end

local function _switch_focus()
  if _state.focus == "agents" then
    _state.focus = "tasks"
    if _state.task_win and vim.api.nvim_win_is_valid(_state.task_win) then
      vim.api.nvim_set_current_win(_state.task_win)
    end
  else
    _state.focus = "agents"
    if _state.main_win and vim.api.nvim_win_is_valid(_state.main_win) then
      vim.api.nvim_set_current_win(_state.main_win)
    end
  end
  _render_tasks()
  _render_main()
end

local function _enter_detail()
  if _state.mode == "detail" then return end
  local agent = _selected_agent()
  if not agent then
    vim.notify("Zephyrus: no agent selected", vim.log.levels.WARN)
    return
  end
  _state.mode = "detail"
  _state.detail_agent = agent
  if _state.main_win and vim.api.nvim_win_is_valid(_state.main_win) then
    vim.wo[_state.main_win].wrap = true
  end
  _render_main()
  -- Scroll to bottom to show latest output
  local lc = vim.api.nvim_buf_line_count(_state.main_buf)
  pcall(vim.api.nvim_win_set_cursor, _state.main_win, { lc, 0 })
end

local function _exit_detail()
  if _state.mode ~= "detail" then return end
  _state.mode = "cards"
  _state.detail_agent = nil
  if _state.main_win and vim.api.nvim_win_is_valid(_state.main_win) then
    vim.wo[_state.main_win].wrap = false
  end
  _render_main()
end

-- ============================================================
-- Actions
-- ============================================================

local function _action_focus_pane()
  local agent = _active_agent()
  if not agent then return end
  local pane = safe_str(agent.tmux_pane)
  if not pane then
    vim.notify("Zephyrus: no tmux pane for this agent", vim.log.levels.WARN)
    return
  end
  vim.fn.system(string.format("tmux select-pane -t %s", pane))
  vim.notify(string.format("Focused pane %s (%s)", pane, safe_str(agent.name) or ""), vim.log.levels.INFO)
end

local function _action_send_instruction()
  local agent = _active_agent()
  if not agent then
    vim.notify("Zephyrus: no agent selected", vim.log.levels.WARN)
    return
  end
  local label = safe_str(agent.name) or (safe_str(agent.id) or "?"):sub(1, 12)
  vim.ui.input({ prompt = string.format("Instruction for %s: ", label) }, function(text)
    if not text or text == "" then return end
    local result, err = _req("POST", "/agents/" .. agent.id .. "/send", { text = text })
    if result then
      vim.notify(string.format("Sent to %s: %s", label, text:sub(1, 50)), vim.log.levels.INFO)
    else
      vim.notify("Zephyrus: " .. (err or "send failed"), vim.log.levels.ERROR)
    end
  end)
end

local function _action_show_diff()
  local agent = _active_agent()
  local ct = agent and safe_str(agent.current_task)
  if not ct then
    vim.notify("Zephyrus: agent has no current task", vim.log.levels.WARN)
    return
  end
  local diff, err = _req("GET", "/tasks/" .. ct .. "/diff?project_path=.")
  if not diff then
    vim.notify("Zephyrus: " .. (err or "diff failed"), vim.log.levels.ERROR)
    return
  end
  local label = safe_str(agent.name) or (safe_str(agent.id) or "?"):sub(1, 12)
  local float = ui.create_float("Diff: " .. label, 0.70, 0.60)
  if float.buf ~= -1 then
    ui.render_diff(float.buf, diff)
  end
end

local function _action_merge()
  local agent = _active_agent()
  local task_id = agent and safe_str(agent.current_task)
  if not task_id then
    vim.notify("Zephyrus: agent has no current task", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = string.format("Merge task %s? (y/N): ", task_id:sub(1, 12)) }, function(confirm)
    if confirm ~= "y" and confirm ~= "Y" then return end
    local result, err = _req("POST", "/tasks/" .. task_id .. "/merge?project_path=.&target=main")
    if result then
      vim.notify("Merged: " .. (result.message or "ok"), vim.log.levels.INFO)
      _refresh()
    else
      vim.notify("Zephyrus: " .. (err or "merge failed"), vim.log.levels.ERROR)
    end
  end)
end

local function _action_reject()
  local agent = _active_agent()
  local task_id = agent and safe_str(agent.current_task)
  if not task_id then
    vim.notify("Zephyrus: agent has no current task", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "Rejection reason: " }, function(reason)
    if not reason or reason == "" then return end
    local result, err = _req("POST", "/tasks/" .. task_id .. "/reject", { reason = reason })
    if result then
      vim.notify(string.format("Rejected task %s", task_id:sub(1, 12)), vim.log.levels.INFO)
      _refresh()
    else
      vim.notify("Zephyrus: " .. (err or "reject failed"), vim.log.levels.ERROR)
    end
  end)
end

local function _action_assign()
  local agent = _active_agent()
  if not agent then
    vim.notify("Zephyrus: no agent selected", vim.log.levels.WARN)
    return
  end
  local result, err = _req("POST", "/agents/" .. agent.id .. "/assign")
  if result then
    vim.notify(string.format("Assigned %s to %s", (result.task_id or ""):sub(1, 12), safe_str(agent.name) or ""), vim.log.levels.INFO)
    _refresh()
  else
    vim.notify("Zephyrus: " .. (err or "no tasks available"), vim.log.levels.ERROR)
  end
end

local function _action_pause()
  local agent = _active_agent()
  if not agent then
    vim.notify("Zephyrus: no agent selected", vim.log.levels.WARN)
    return
  end
  local result, err = _req("POST", "/agents/" .. agent.id .. "/pause")
  if result then
    vim.notify(string.format("Agent %s → %s", safe_str(agent.name) or "?", result.status or ""), vim.log.levels.INFO)
    _refresh()
  else
    vim.notify("Zephyrus: " .. (err or "pause failed"), vim.log.levels.ERROR)
  end
end

local function _action_new_task()
  vim.ui.input({ prompt = "Task title: " }, function(title)
    if not title or title == "" then return end
    vim.ui.input({ prompt = "Priority (0-9, default 5): " }, function(pri_str)
      local priority = tonumber(pri_str) or 5
      priority = math.max(0, math.min(9, priority))
      vim.ui.input({ prompt = "Description (optional): " }, function(desc)
        local result, err = _req("POST", "/tasks", {
          title = title,
          description = desc or "",
          priority = priority,
          tags = {},
          depends_on = {},
          created_by = "nvim",
        })
        if result then
          vim.notify(string.format("Created: %s", title), vim.log.levels.INFO)
          _refresh()
        else
          vim.notify("Zephyrus: " .. (err or "create failed"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

-- ============================================================
-- Keymaps
-- ============================================================

local function _setup_keymaps()
  local tbuf = _state.task_buf
  local mbuf = _state.main_buf
  local o = { nowait = true, silent = true }

  -- Helper for buffer-local keymaps
  local function tmap(key, fn, desc)
    vim.keymap.set("n", key, fn, vim.tbl_extend("force", o, { buffer = tbuf, desc = "Zeph: " .. desc }))
  end
  local function mmap(key, fn, desc)
    vim.keymap.set("n", key, fn, vim.tbl_extend("force", o, { buffer = mbuf, desc = "Zeph: " .. desc }))
  end

  -- ---- Task pane ----
  tmap("j",      function() _task_nav(1) end,  "Next task")
  tmap("k",      function() _task_nav(-1) end, "Prev task")
  tmap("<Down>", function() _task_nav(1) end,  "Next task")
  tmap("<Up>",   function() _task_nav(-1) end, "Prev task")
  tmap("<Tab>",  _switch_focus,                 "Switch to agents")
  tmap("N",      _action_new_task,              "New task")
  tmap("r",      _refresh,                      "Refresh")
  tmap("R",      _refresh,                      "Refresh")
  tmap("q",      function() M.close() end,     "Close dashboard")

  -- ---- Main pane (cards + detail) ----
  mmap("j",      function() _agent_nav(1) end,  "Next agent / scroll")
  mmap("k",      function() _agent_nav(-1) end, "Prev agent / scroll")
  mmap("<Down>", function() _agent_nav(1) end,  "Next agent / scroll")
  mmap("<Up>",   function() _agent_nav(-1) end, "Prev agent / scroll")
  mmap("<CR>",   function()
    if _state.mode == "cards" then
      _enter_detail()
    else
      _action_focus_pane()
    end
  end, "Enter detail / focus pane")
  mmap("<Esc>",  _exit_detail,                   "Back to cards")
  mmap("<BS>",   _exit_detail,                   "Back to cards")
  mmap("i",      _action_send_instruction,       "Send instruction")
  mmap("d",      _action_show_diff,              "Show diff")
  mmap("m",      _action_merge,                  "Merge task")
  mmap("x",      _action_reject,                 "Reject task")
  mmap("a",      _action_assign,                 "Assign task")
  mmap("p",      _action_pause,                  "Pause/resume")
  mmap("<Tab>",  _switch_focus,                  "Switch to tasks")
  mmap("r",      _refresh,                       "Refresh")
  mmap("R",      _refresh,                       "Refresh")
  mmap("q",      function() M.close() end,      "Close dashboard")
  mmap("G",      function()
    if _state.mode == "detail" then
      local lc = vim.api.nvim_buf_line_count(_state.main_buf)
      pcall(vim.api.nvim_win_set_cursor, _state.main_win, { lc, 0 })
    end
  end, "Scroll to bottom")
end

-- ============================================================
-- Public API
-- ============================================================

function M.open()
  -- Close existing dashboard if open
  if _is_open() then
    M.close()
  end

  -- Create new tab
  vim.cmd("tabnew")
  _state.tab = vim.api.nvim_get_current_tabpage()

  -- Current window becomes the right/main pane
  _state.main_win = vim.api.nvim_get_current_win()
  _state.main_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(_state.main_win, _state.main_buf)

  -- Create left pane for tasks
  vim.cmd("topleft vnew")
  _state.task_win = vim.api.nvim_get_current_win()
  _state.task_buf = vim.api.nvim_get_current_buf()

  -- Size left pane to ~28% width
  local total_width = vim.o.columns
  local task_width = math.max(30, math.floor(total_width * 0.28))
  vim.api.nvim_win_set_width(_state.task_win, task_width)
  vim.wo[_state.task_win].winfixwidth = true

  -- Configure buffer options
  for _, buf in ipairs({ _state.task_buf, _state.main_buf }) do
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "zephyrus"
  end

  -- Configure window options
  for _, win in ipairs({ _state.task_win, _state.main_win }) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = false
    vim.wo[win].spell = false
  end

  -- Initialize state
  _state.mode = "cards"
  _state.focus = "agents"
  _state.sel_agent = 1
  _state.sel_task = 1
  _state.detail_agent = nil

  -- Setup keymaps
  _setup_keymaps()

  -- Initial data fetch and render
  _state.tasks = _fetch_tasks()
  _state.agents = _fetch_agents()
  _render_tasks()
  _render_main()

  -- Focus the main (agents) pane
  vim.api.nvim_set_current_win(_state.main_win)

  -- Auto-refresh timer (every 3 seconds)
  local timer = vim.loop.new_timer()
  _state.auto_timer = timer
  timer:start(3000, 3000, vim.schedule_wrap(function()
    if not _is_open() then
      timer:stop()
      timer:close()
      _state.auto_timer = nil
      return
    end
    _refresh()
  end))

  -- Cleanup on buffer wipe (handles :q, :bd, etc.)
  for _, buf in ipairs({ _state.task_buf, _state.main_buf }) do
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        M.close()
      end,
    })
  end
end

function M.close()
  -- Guard against re-entrancy from BufWipeout autocmds
  if not _state.tab then return end

  -- Stop timer
  if _state.auto_timer then
    pcall(function()
      _state.auto_timer:stop()
      _state.auto_timer:close()
    end)
    _state.auto_timer = nil
  end

  -- Save buffer refs and clear state first (prevents re-entrancy)
  local bufs = { _state.task_buf, _state.main_buf }
  _state.tab = nil
  _state.task_win = nil
  _state.task_buf = nil
  _state.main_win = nil
  _state.main_buf = nil
  _state.mode = "cards"
  _state.detail_agent = nil

  -- Delete buffers (which closes their windows and the tab)
  for _, buf in ipairs(bufs) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

function M.refresh()
  if _is_open() then
    _refresh()
    return true
  end
  return false
end

return M
