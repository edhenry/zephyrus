# Zephyrus Command Center — Design Document

## Vision

A **terminal-native multi-agent orchestration environment** built on tmux + Neovim + a lightweight coordination daemon. Unlike tools that give you parallel terminals with status badges (e.g., Maestro), Zephyrus Command Center provides **coordinated agents operating on a shared task model** — where agents and the human operator push and pop work from a common stack, review each other's output, and converge on a unified codebase.

The philosophy: **tmux is the window manager, Neovim is the IDE, and a thin coordination layer is the glue.** No Electron. No Tauri. No browser. Just terminals, all the way down.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        ZEPHYRUS COMMAND CENTER                           │
│                                                                          │
│  ┌─────────────┐  ┌──────────────────────────┐  ┌────────────────────┐  │
│  │  TASK BOARD  │  │      AGENT GRID          │  │   REVIEW PANE      │  │
│  │             │  │  ┌──────────┬──────────┐  │  │                    │  │
│  │  ▶ task-1   │  │  │ agent-1  │ agent-2  │  │  │  nvim              │  │
│  │    task-2   │  │  │ claude   │ claude   │  │  │  (diffview /       │  │
│  │    task-3   │  │  │ WORKING  │ IDLE     │  │  │   code review /    │  │
│  │    task-4   │  │  ├──────────┼──────────┤  │  │   merge assist)    │  │
│  │    task-5   │  │  │ agent-3  │ agent-4  │  │  │                    │  │
│  │             │  │  │ gemini   │ shell    │  │  │                    │  │
│  │  ─────────  │  │  │ REVIEW   │ DONE     │  │  │                    │  │
│  │  completed: │  │  └──────────┴──────────┘  │  │                    │  │
│  │  ✓ task-0   │  │                            │  │                    │  │
│  └─────────────┘  └──────────────────────────┘  └────────────────────┘  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │                    GIT PANEL (lazygit / git graph)               │    │
│  └──────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ╔══════════════════════════════════════════════════════════════════╗    │
│  ║ STATUS: agents:4 │ tasks:5/12 │ worktrees:4 │ mcp:3 │ 14:32:07║    │
│  ╚══════════════════════════════════════════════════════════════════╝    │
└──────────────────────────────────────────────────────────────────────────┘
```

### System Components

```
                    ┌─────────────────────┐
                    │   zephd (daemon)    │
                    │   ─────────────     │
                    │   Task Stack        │
                    │   Agent Registry    │
                    │   Worktree Manager  │
                    │   MCP Router        │
                    │   Event Bus         │
                    │                     │
                    │   REST API :9800    │
                    │   WebSocket :9801   │
                    └──────┬──────────────┘
                           │
              ┌────────────┼────────────────┐
              │            │                │
     ┌────────▼───┐  ┌────▼──────┐  ┌──────▼──────┐
     │ zeph CLI   │  │ MCP Server│  │ Neovim      │
     │ (user)     │  │ (agents)  │  │ Plugin      │
     │            │  │           │  │             │
     │ push/pop   │  │ push/pop  │  │ task list   │
     │ status     │  │ status    │  │ diff review │
     │ launch     │  │ heartbeat │  │ merge       │
     └────────────┘  └───────────┘  └─────────────┘
              │            │                │
              └────────────┼────────────────┘
                           │
                    ┌──────▼──────────────┐
                    │   tmux (display)    │
                    │   ─────────────     │
                    │   Layout engine     │
                    │   Pane management   │
                    │   Status line       │
                    └─────────────────────┘
```

---

## Core Components

### 1. The Coordination Daemon — `zephd`

The brain of the system. A lightweight, single-binary daemon that manages all shared state.

**Language choice: Python (FastAPI + uvicorn).**
Rationale: fast to build, async-native, the entire Zephyrus ecosystem already assumes Python availability, and the daemon is I/O-bound (not CPU-bound), so Python's performance is more than sufficient. Can always rewrite the hot path in Rust later if needed.

#### 1.1 Task Stack

The central data structure. A priority queue with stack-like semantics where both agents and the human can push and pop work.

```
Task {
    id:           string       # unique identifier (ulid)
    title:        string       # short description
    description:  string       # detailed requirements, context, acceptance criteria
    status:       enum         # pending | claimed | in_progress | in_review | done | failed | blocked
    priority:     int          # 0 (highest) to 9 (lowest)
    created_by:   string       # "user" or agent-id
    assigned_to:  string?      # agent-id or null (unclaimed)
    depends_on:   string[]     # task IDs that must complete first
    branch:       string?      # git branch for this task's work
    worktree:     string?      # path to isolated worktree
    tags:         string[]     # labels for filtering (e.g., "frontend", "bugfix")
    created_at:   timestamp
    updated_at:   timestamp
    output:       string?      # agent's summary of what was done
}
```

**Operations:**

| Operation | Who | Description |
|-----------|-----|-------------|
| `push` | user, agent | Add a new task to the stack |
| `pop` | agent | Claim the highest-priority unclaimed task whose dependencies are satisfied |
| `peek` | user, agent | View the task stack without claiming |
| `update` | user, agent | Update task status, add output, change priority |
| `complete` | agent | Mark task done with output summary |
| `fail` | agent | Mark task failed with error details |
| `block` | agent | Mark task blocked, optionally push a new subtask |
| `reassign` | user | Move a task to a different agent or back to unclaimed |
| `decompose` | user, agent | Split a task into subtasks with dependency links |

**Dependency resolution:** A task can only be popped if all `depends_on` tasks have status `done`. This enables natural workflows like "agent-1 builds the API, agent-2 builds the frontend that depends on it."

**Storage:** SQLite file at `~/.zephyrus/state/tasks.db`. Survives daemon restarts. Simple, zero-config, battle-tested.

#### 1.2 Agent Registry

Tracks all active agent sessions.

```
Agent {
    id:           string       # unique identifier
    name:         string       # display name ("claude-1", "gemini-2")
    mode:         enum         # claude | gemini | codex | aider | shell
    status:       enum         # starting | idle | working | waiting | done | error
    session_id:   int          # tmux pane ID
    worktree:     string?      # current worktree path
    current_task: string?      # task ID being worked on
    pid:          int          # process ID
    started_at:   timestamp
    last_seen:    timestamp    # heartbeat tracking
    mcp_servers:  string[]     # MCP servers loaded for this agent
}
```

**Heartbeat:** Agents must check in every 30 seconds via MCP or the daemon marks them `error` after 90 seconds of silence. The heartbeat carries current status, enabling the dashboard to update in real-time.

#### 1.3 Worktree Manager

Manages git worktree lifecycle, similar to Maestro's approach but integrated with the task stack.

**Path scheme:**
```
~/.zephyrus/worktrees/{repo-name}/{task-id-or-branch}/
```

**Lifecycle:**
1. When a task is claimed → create a worktree on a branch named `zeph/{task-id}`
2. When a task completes → worktree remains for review
3. When a task is merged → cleanup worktree and prune
4. When the user requests → bulk cleanup of stale worktrees

**Branch naming convention:**
```
zeph/{task-id}          # e.g., zeph/01HQXYZ-add-auth
zeph/{task-id}/subtask  # for decomposed tasks
```

#### 1.4 MCP Router

A meta-MCP server that can:
- **Discover** MCP server configs from project `.mcp.json`, `~/.zephyrus/mcp/`, and agent-specific configs
- **Inject** selected MCP servers into agent sessions at launch time
- **Proxy** MCP tool calls between agents and servers
- **Expose Zephyrus tools** to agents via MCP:

```json
{
  "tools": [
    {
      "name": "zeph_task_push",
      "description": "Add a new task to the shared task stack",
      "inputSchema": {
        "type": "object",
        "properties": {
          "title": { "type": "string" },
          "description": { "type": "string" },
          "priority": { "type": "integer", "minimum": 0, "maximum": 9 },
          "depends_on": { "type": "array", "items": { "type": "string" } },
          "tags": { "type": "array", "items": { "type": "string" } }
        },
        "required": ["title"]
      }
    },
    {
      "name": "zeph_task_pop",
      "description": "Claim the next available task from the stack"
    },
    {
      "name": "zeph_task_update",
      "description": "Update the current task's status",
      "inputSchema": {
        "type": "object",
        "properties": {
          "status": { "type": "string", "enum": ["in_progress", "in_review", "done", "failed", "blocked"] },
          "output": { "type": "string" }
        },
        "required": ["status"]
      }
    },
    {
      "name": "zeph_status",
      "description": "Report agent status to the command center",
      "inputSchema": {
        "type": "object",
        "properties": {
          "state": { "type": "string", "enum": ["idle", "working", "waiting", "done", "error"] },
          "message": { "type": "string" }
        },
        "required": ["state"]
      }
    },
    {
      "name": "zeph_agent_list",
      "description": "List all active agents and their current tasks"
    }
  ]
}
```

This is the key differentiator from Maestro: agents can **coordinate through the task stack** rather than operating in isolation.

#### 1.5 Event Bus

WebSocket-based pub/sub for real-time updates. Subscribers:
- tmux status line script (polls or connects via WebSocket)
- Neovim plugin (Lua WebSocket client or HTTP polling)
- The TUI dashboard (curses-based or textual)
- The `zeph` CLI (for watch mode)

Events:
```
task.created    { task }
task.claimed    { task, agent }
task.updated    { task }
task.completed  { task, agent, output }
task.failed     { task, agent, error }
agent.started   { agent }
agent.status    { agent, status }
agent.stopped   { agent }
worktree.created { path, branch, task }
worktree.removed { path }
```

#### 1.6 REST API

```
POST   /tasks              # push a task
GET    /tasks              # list all tasks (filterable by status, tags, assigned_to)
GET    /tasks/:id          # get task details
PATCH  /tasks/:id          # update task
POST   /tasks/:id/pop      # claim a task (agent auth required)
POST   /tasks/:id/complete # mark done with output
DELETE /tasks/:id          # remove task

GET    /agents             # list all agents
POST   /agents             # register a new agent
PATCH  /agents/:id         # update agent status / heartbeat
DELETE /agents/:id         # deregister

GET    /worktrees          # list all worktrees
POST   /worktrees          # create a worktree for a task
DELETE /worktrees/:path    # cleanup

GET    /mcp/servers        # list discovered MCP servers
POST   /mcp/servers        # register a custom MCP server
GET    /mcp/agents/:id     # get MCP config for an agent

GET    /ws                 # WebSocket event stream
```

---

### 2. The CLI — `zeph`

The primary human interface for interacting with the command center from any terminal.

```bash
# Task management
zeph push "Add user authentication" --priority 2 --tags auth,backend
zeph push "Write tests for auth" --depends-on 01HQXYZ
zeph ls                          # list tasks
zeph ls --status pending         # filter
zeph ls --tag frontend           # filter by tag
zeph show 01HQXYZ                # task details
zeph edit 01HQXYZ                # open task in $EDITOR
zeph done 01HQXYZ "Implemented JWT auth with refresh tokens"
zeph fail 01HQXYZ "Blocked on missing API spec"
zeph reassign 01HQXYZ claude-2
zeph decompose 01HQXYZ           # interactive: split task into subtasks

# Agent management
zeph agents                      # list agents with status
zeph launch claude --name claude-1 --branch feature/auth
zeph launch gemini --name gemini-1
zeph launch shell --name debug-shell
zeph stop claude-1
zeph stop --all

# Orchestration
zeph up                          # start the daemon + full command center layout
zeph up --agents 4 --mode claude # start with 4 claude agents
zeph down                        # graceful shutdown of everything
zeph layout solo                 # 1 agent + review + git
zeph layout pair                 # 2 agents + review + git
zeph layout squad                # 4 agents + review + git
zeph layout full                 # 6 agents + review + git

# Review workflow
zeph review 01HQXYZ              # open task's changes in nvim diffview
zeph merge 01HQXYZ               # merge task branch into target
zeph diff 01HQXYZ                # show diff summary

# MCP management
zeph mcp ls                      # list available MCP servers
zeph mcp enable server-name      # enable for new agent sessions
zeph mcp disable server-name
zeph mcp add ./path/to/server    # register custom server

# Worktree management
zeph worktrees                   # list all active worktrees
zeph worktrees clean             # remove completed/stale worktrees

# Dashboard
zeph dash                        # launch the TUI dashboard in current pane
zeph status                      # one-shot status summary
```

---

### 3. tmux Layout Engine

Predefined layouts that arrange panes for different workflows. Each layout is a declarative YAML spec.

#### Layout: `solo` (1 agent)
```
┌────────────────────┬───────────────────────────┐
│                    │                           │
│   Agent Terminal   │   Neovim (Review)         │
│   (60%)            │   (40%)                   │
│                    │                           │
│                    │                           │
├────────────────────┴───────────────────────────┤
│   lazygit (30%)                                │
└────────────────────────────────────────────────┘
```

#### Layout: `pair` (2 agents)
```
┌─────────┬──────────┬───────────────────────────┐
│         │          │                           │
│ Agent 1 │ Agent 2  │   Neovim (Review)         │
│ (30%)   │ (30%)    │   (40%)                   │
│         │          │                           │
│         │          │                           │
├─────────┴──────────┴───────────────────────────┤
│   lazygit (30%)                                │
└────────────────────────────────────────────────┘
```

#### Layout: `squad` (4 agents)
```
┌──────────┬──────────┬──────────────────────────┐
│ Agent 1  │ Agent 2  │                          │
│          │          │   Neovim (Review)         │
├──────────┼──────────┤   (40%)                  │
│ Agent 3  │ Agent 4  │                          │
│          │          │                          │
├──────────┴──────────┴──────────────────────────┤
│   lazygit (25%)                                │
└────────────────────────────────────────────────┘
```

#### Layout: `full` (6 agents, git as overlay)
```
┌──────────┬──────────┬──────────────────────────┐
│ Agent 1  │ Agent 2  │ Agent 3                  │
│          │          │                          │
├──────────┼──────────┼──────────────────────────┤
│ Agent 4  │ Agent 5  │ Agent 6                  │
│          │          │                          │
├──────────┴──────────┴──────────────────────────┤
│   Task Board (left 25%) │ Status + Controls    │
└────────────────────────────────────────────────┘
```

#### Layout Definition Format
```yaml
# ~/.zephyrus/layouts/pair.yaml
name: pair
description: "2 agents with review pane and git panel"
panes:
  - id: agent-1
    type: agent
    mode: claude
    position: { row: 0, col: 0 }
    size: { width: 30%, height: 70% }
  - id: agent-2
    type: agent
    mode: claude
    position: { row: 0, col: 1 }
    size: { width: 30%, height: 70% }
  - id: review
    type: nvim
    args: ["+DiffviewOpen"]
    position: { row: 0, col: 2 }
    size: { width: 40%, height: 70% }
  - id: git
    type: lazygit
    position: { row: 1, col: 0 }
    size: { width: 100%, height: 30% }
status_bar:
  left: "agents:{agent_count} | tasks:{pending_count}/{total_count}"
  right: "worktrees:{worktree_count} | {time}"
```

---

### 4. Neovim Integration — `zephyrus-cc.nvim`

A Neovim plugin that connects to the daemon and provides in-editor access to the command center.

#### Features

**Task Board Floating Window (`<leader>zt`)**
- Displays the task stack in a floating window (similar to Trouble.nvim)
- Keybindings: `a` add task, `d` mark done, `e` edit, `p` change priority, `r` reassign
- Auto-refreshes via daemon events
- Color-coded by status: red=blocked, yellow=in_progress, green=done, blue=claimed

**Review Mode (`<leader>zr`)**
- Fetches the diff for a task's worktree
- Opens DiffviewOpen against the target branch
- Inline approve/reject comments (stored as task metadata)
- One-keypress merge when satisfied

**Agent Status in Statusline**
- Lualine component showing: `agents: 2W 1I 1R` (working/idle/review)
- Clicking cycles through agent details

**MCP Server Browser (`<leader>zm`)**
- Telescope picker listing all discovered MCP servers
- Toggle enable/disable per server
- Preview server tool definitions
- Add custom servers

**Agent Pane Focus (`<leader>z1` through `<leader>z6`)**
- Quick-jump to agent tmux panes from Neovim
- Uses tmux `select-pane` under the hood

**Task-Aware Branching**
- When opening a file, shows which task/agent owns the worktree in winbar
- Warns if you're editing in an agent's worktree directly

---

### 5. The TUI Dashboard — `zeph dash`

A terminal UI (built with Python `textual` or `urwid`) for when you want a dedicated monitoring view.

```
┌─ ZEPHYRUS COMMAND CENTER ──────────────────────────────────────────┐
│                                                                     │
│  TASK STACK                          AGENTS                         │
│  ─────────                           ──────                         │
│  #1 [P0] ▶ Add JWT authentication    claude-1  ● WORKING  #1       │
│  #2 [P1]   Build user profile page   claude-2  ● IDLE     --       │
│  #3 [P1]   Write API tests           gemini-1  ● WORKING  #4       │
│  #4 [P2] ▶ Fix CORS headers          shell-1   ○ STOPPED  --       │
│  #5 [P3]   Update README                                           │
│  #6 [P3]   Add CI pipeline           WORKTREES                     │
│                                      ─────────                      │
│  COMPLETED                           zeph/01HQ-add-auth  claude-1   │
│  ─────────                           zeph/01HR-fix-cors  gemini-1   │
│  ✓ #0 Setup project structure        main (3 agents)                │
│  ✓ #7 Configure linting                                            │
│                                      MCP SERVERS                    │
│  BLOCKED                             ──────────                     │
│  ───────                             ● filesystem    [all agents]   │
│  ✕ #8 Deploy to staging              ● github        [claude-1,2]  │
│    └─ depends on: #1, #3             ○ slack         [disabled]     │
│                                      ● custom-db     [gemini-1]    │
│                                                                     │
│  [a]dd task  [d]one  [l]aunch agent  [s]top agent  [r]eview  [q]uit│
└─────────────────────────────────────────────────────────────────────┘
```

**Keybindings:**
- `a` — push a new task (inline editor)
- `d` — mark selected task done
- `e` — edit selected task
- `Enter` — view task details / agent output
- `l` — launch a new agent (mode picker)
- `s` — stop selected agent
- `r` — open review for selected task (jumps to nvim pane)
- `m` — MCP server management
- `g` — jump to lazygit pane
- `1-6` — focus agent pane
- `q` — quit dashboard (agents keep running)
- `/` — filter tasks
- `Tab` — cycle focus between panels

---

### 6. Agent Launch & MCP Injection

When an agent is launched, the system:

1. **Creates a worktree** (if task assigned) or uses the project root
2. **Writes `.mcp.json`** into the worktree with:
   - `zephyrus-mcp-server` — exposes `zeph_task_push`, `zeph_task_pop`, `zeph_task_update`, `zeph_status`
   - Any project-level MCP servers from the project's own config
   - User-enabled MCP servers from `~/.zephyrus/mcp/`
3. **Injects environment variables:**
   ```
   ZEPH_AGENT_ID=claude-1
   ZEPH_DAEMON_URL=http://localhost:9800
   ZEPH_SESSION_ID=<unique>
   ZEPH_WORKTREE=/path/to/worktree
   ZEPH_TASK_ID=01HQXYZ  (if pre-assigned)
   ```
4. **Spawns the agent** in a tmux pane with the appropriate CLI:
   ```bash
   # Claude Code
   claude --dangerously-skip-permissions  # or configured flags

   # Gemini CLI
   gemini

   # Aider
   aider --model claude-3.5-sonnet

   # Plain shell
   $SHELL
   ```
5. **Registers the agent** with the daemon
6. **Sends initial prompt** (if task assigned):
   ```
   You are agent {name} in the Zephyrus Command Center.
   Your current task: {task.title}
   Description: {task.description}
   Branch: {task.branch}

   Use the zeph_task_update tool to report progress.
   Use zeph_task_push to create subtasks if needed.
   Use zeph_task_pop to get your next task when done.
   ```

---

### 7. Review & Merge Workflow

This is where the human stays in control.

```
Agent completes task
        │
        ▼
  task.status = "in_review"
        │
        ▼
  User sees status change in:
  - tmux status bar
  - TUI dashboard
  - Neovim task board
        │
        ▼
  User runs: zeph review <task-id>
  (or <leader>zr in Neovim)
        │
        ▼
  DiffView opens showing:
  - All changes on zeph/{task-id} branch
  - Against target branch (main or parent task branch)
        │
        ├── Approve ──► zeph merge <task-id>
        │               - merges branch
        │               - cleans up worktree
        │               - marks task done
        │               - unblocks dependent tasks
        │
        ├── Request Changes ──► zeph reject <task-id> "needs X"
        │                       - sends feedback to agent
        │                       - task goes back to in_progress
        │
        └── Take Over ──► zeph claim <task-id>
                          - reassigns to human
                          - opens worktree in nvim
```

---

## Directory Structure

```
zephyrus/
├── bin/
│   ├── bootstrap.sh              # Enhanced setup
│   ├── devinit.sh                # Project scaffolding
│   ├── zeph                      # CLI entrypoint (shell wrapper)
│   └── zephd                     # Daemon launcher
├── kitty/                        # (existing)
├── nvim/
│   └── init.lua                  # (existing, extended)
├── tmux/
│   ├── tmux.conf                 # (existing, extended)
│   └── layouts/                  # Layout definitions
│       ├── solo.yaml
│       ├── pair.yaml
│       ├── squad.yaml
│       └── full.yaml
├── daemon/                       # zephd — coordination daemon
│   ├── pyproject.toml
│   ├── zephd/
│   │   ├── __init__.py
│   │   ├── main.py               # FastAPI app + uvicorn entry
│   │   ├── models.py             # Task, Agent, Worktree schemas
│   │   ├── db.py                 # SQLite via aiosqlite
│   │   ├── task_stack.py         # Task stack logic + dependency resolution
│   │   ├── agent_registry.py     # Agent lifecycle management
│   │   ├── worktree_manager.py   # Git worktree operations
│   │   ├── mcp_router.py         # MCP server discovery + config injection
│   │   ├── event_bus.py          # WebSocket pub/sub
│   │   └── layout_engine.py      # tmux layout management
│   └── tests/
├── cli/                          # zeph — CLI tool
│   ├── pyproject.toml
│   └── zeph/
│       ├── __init__.py
│       ├── main.py               # Click/Typer CLI
│       ├── client.py             # HTTP client for daemon
│       └── commands/
│           ├── tasks.py
│           ├── agents.py
│           ├── worktrees.py
│           ├── mcp.py
│           └── layout.py
├── mcp-server/                   # zephyrus-mcp-server
│   ├── pyproject.toml
│   └── zeph_mcp/
│       ├── __init__.py
│       ├── server.py             # MCP protocol (stdio JSON-RPC)
│       └── tools.py              # zeph_task_push/pop/update/status
├── nvim-plugin/                  # zephyrus-cc.nvim
│   └── lua/
│       └── zephyrus_cc/
│           ├── init.lua
│           ├── task_board.lua
│           ├── review.lua
│           ├── statusline.lua
│           └── mcp_browser.lua
├── tui/                          # zeph dash
│   ├── pyproject.toml
│   └── zeph_tui/
│       ├── __init__.py
│       ├── app.py                # Textual app
│       ├── task_panel.py
│       ├── agent_panel.py
│       └── mcp_panel.py
├── zephyrus/                     # (existing core assets)
├── docs/
│   └── DESIGN.md                 # This file
├── README.md
└── LICENSE
```

---

## Implementation Phases

### Phase 1: Foundation (daemon + CLI + basic tmux layout)

**Goal:** Get the core loop working — push tasks, launch agents, agents pop tasks, report status.

1. Scaffold `daemon/` with FastAPI
2. Implement Task Stack with SQLite storage
3. Implement Agent Registry (in-memory with heartbeat)
4. Build the `zeph` CLI with `push`, `pop`, `ls`, `agents`, `launch`, `stop`
5. Build basic tmux layout engine (`solo` and `pair` layouts)
6. Write `zeph up` / `zeph down` for lifecycle management

**Deliverable:** Can launch 2 agents, push tasks, agents claim tasks via CLI, status visible in tmux status bar.

### Phase 2: MCP Integration (agents coordinate through tools)

**Goal:** Agents can push/pop/update tasks via MCP tools, not just the CLI.

1. Build `mcp-server/` implementing the Zephyrus tool set
2. Build MCP config injection into agent launch flow
3. Implement MCP server discovery (project `.mcp.json` + user config)
4. Add WebSocket event bus for real-time updates
5. Build tmux status line integration (event-driven updates)

**Deliverable:** Claude Code agents autonomously claim tasks, report progress, create subtasks, and flag items for review — all via MCP tools.

### Phase 3: Review & Git Workflow

**Goal:** Smooth human-in-the-loop review and merge cycle.

1. Implement Worktree Manager with task-linked lifecycle
2. Build `zeph review` / `zeph merge` / `zeph reject` commands
3. Build `nvim-plugin/` with DiffView integration
4. Integrate lazygit as a managed pane in layouts
5. Add `squad` and `full` layouts

**Deliverable:** Full cycle — push task → agent claims → agent works in isolated worktree → agent flags for review → human reviews in nvim → merge → next task unblocks.

### Phase 4: TUI Dashboard & Polish

**Goal:** Rich monitoring experience and production-quality UX.

1. Build `tui/` with Textual
2. Neovim task board floating window
3. Neovim statusline component
4. Session persistence (survive daemon restart)
5. Agent prompt templates and customization
6. Custom layout definition support

**Deliverable:** Full command center experience with live dashboard, in-editor task management, and customizable workflows.

---

## Design Principles

1. **Terminal-native.** No browser, no Electron, no GUI toolkit. tmux + Neovim + TUI. The entire system works over SSH.

2. **Agents are first-class participants.** They can push tasks, not just consume them. An agent discovering a bug can create a task for another agent (or the human) to handle.

3. **Human stays in the loop.** All merges require human review. The task stack is transparent. The human can intervene at any point — reassign, reprioritize, take over.

4. **Composition over frameworks.** Each component (daemon, CLI, MCP server, nvim plugin, TUI) is independent and useful on its own. The CLI works without the TUI. The MCP server works without the nvim plugin. Mix and match.

5. **tmux is the window manager.** Don't fight it. Use tmux's native pane/window/session model. Layout definitions are just instructions for `tmux split-window` and `tmux resize-pane`.

6. **SQLite is the database.** No Redis, no Postgres, no message queue. A single SQLite file handles all persistence. It's local, it's fast, it's zero-config, and it handles the concurrency level we need (dozens of agents, not thousands).

7. **MCP is the coordination protocol.** Agents don't need a custom SDK. They just need MCP tool access — which Claude Code, Gemini CLI, and others already support natively. The `zephyrus-mcp-server` is the bridge.

8. **Graceful degradation.** If the daemon dies, agents keep running (they just can't coordinate). If an agent dies, its tasks go back to unclaimed after the heartbeat timeout. If the TUI crashes, the tmux panes are still there.
