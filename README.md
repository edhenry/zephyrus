# Zephyrus — Coding Agent Command Center

A terminal-native multi-agent orchestration environment. Push tasks to a shared stack, launch AI coding agents that claim and execute work, review changes in Neovim, and merge — all from tmux.

Agents coordinate through a shared task stack with priority ordering and dependency resolution. They can push subtasks for each other, report status, and flag work for human review — all via MCP tools.

## Quick Start

```bash
git clone <repo-url> ~/zephyrus   # clone anywhere you like
cd ~/zephyrus
./bin/bootstrap.sh                 # links configs, installs packages
source .venv/bin/activate          # activate the environment
```

First run on a new machine? Use `--deps` to install system dependencies too:

```bash
./bin/bootstrap.sh --deps          # installs neovim, tmux, kitty, etc.
```

This uses `brew bundle` on macOS (via the included `Brewfile`) or `apt` on Linux (via `deps/apt-packages.txt`). Without `--deps`, bootstrap only links configs and installs Python packages — safe to re-run anytime.

### Verify it works

```bash
# Terminal 1 — start the daemon
zephd

# Terminal 2 — use the CLI
source .venv/bin/activate
zeph status
zeph push "My first task" -p 1
zeph ls
```

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│  zeph CLI   │────▶│  zephd       │◀────│ zeph-mcp       │
│  (human)    │     │  (daemon)    │     │ (AI agents)    │
└─────────────┘     │              │     └────────────────┘
                    │  REST :9800  │
┌─────────────┐     │  WebSocket   │     ┌────────────────┐
│  zeph-tui   │────▶│  SQLite DB   │◀────│ nvim plugin    │
│  (Textual)  │     │  Task Stack  │     │ (Lua)          │
└─────────────┘     │  Agent Reg.  │     └────────────────┘
                    │  Worktrees   │
                    └──────────────┘
```

- **zephd** — FastAPI coordination daemon. Task stack with SQLite persistence, in-memory agent registry with heartbeat monitoring, WebSocket event bus, tmux layout engine, git worktree manager, MCP config auto-injection. Runs on port 9800.
- **zeph** — CLI for humans. Push/pop tasks, launch agents, apply layouts, review/merge/reject agent work, manage worktrees and MCP servers.
- **zeph-mcp** — MCP server (JSON-RPC over stdio). Gives AI agents 6 tools to interact with the task stack. Works with Claude Code, Gemini CLI, or any MCP-compatible agent.
- **zeph-tui** — Textual-based TUI dashboard. Live task board, agent panel, WebSocket event log, keyboard-driven workflow.
- **nvim plugin** — Neovim integration. Floating task board, agent panel, statusline, push/review/merge/reject from within your editor.

## Usage

### Daemon

```bash
zephd                        # start in foreground (see logs)
# or
zeph up                      # start daemon in background + tmux layout
zeph down                    # shut everything down
```

The daemon stores state at `~/.zephyrus/state/` (SQLite DB + PID file). Set `ZEPH_PORT` to change the port (default 9800).

### Task Management

Tasks have a title, priority (0 = highest, 9 = lowest), tags, and optional dependencies on other tasks.

```bash
# Push tasks
zeph push "Add user authentication" -p 2 -t backend -t auth
zeph push "Build login UI" -p 3 -t frontend
zeph push "Write auth tests" -p 4 -t testing --depends-on <task-id>

# List tasks
zeph ls                      # active tasks (hides done/failed)
zeph ls --all                # everything
zeph ls -s pending           # filter by status
zeph ls -t frontend          # filter by tag

# Manage tasks
zeph task show <id>          # full task details (prefix match on ID)
zeph task done <id>          # mark complete
zeph task done <id> -o "Implemented JWT with refresh tokens"
zeph task fail <id> -r "Blocked on missing API spec"
zeph task edit <id> -p 0     # change priority
zeph task edit <id> -a <agent-id>  # reassign
zeph task rm <id>            # delete

# Status overview
zeph status
```

Task IDs are ULIDs. You can use prefix matching — `zeph task show 01KG` matches `01KGVETYZ40S...`.

#### Dependency Resolution

When a task has `--depends-on`, it won't be available for agents to pop until all dependencies are `done`:

```bash
zeph push "Build API" -p 1
# note the ID, e.g. 01KGXYZ

zeph push "Build frontend that calls API" -p 2 --depends-on 01KGXYZ
# this task stays pending until 01KGXYZ is done
```

### Agent Management

```bash
zeph agent launch claude -n claude-1    # register an agent
zeph agent launch gemini -n gemini-1
zeph agent ls                           # list agents with status
zeph agent stop claude-1                # deregister
zeph agent stop --all                   # stop all
```

### Review / Merge Workflow

When agents flag tasks as `in_review`, you review and act:

```bash
zeph review review              # list tasks awaiting review
zeph review diff <id>           # see what changed (file list + stats)
zeph review merge <id>          # merge branch into main
zeph review merge <id> -t dev   # merge into a different target
zeph review reject <id> -r "Tests are failing"  # send feedback to agent
```

The reject command sends feedback directly to the agent's tmux pane and resets the task to `in_progress`.

### Git Worktrees

Each task gets an isolated git worktree so agents don't conflict:

```bash
zeph worktree ls                # list all worktrees
zeph worktree rm <path>         # remove a specific worktree
zeph worktree clean             # prune stale worktrees
```

Worktrees are created at `~/.zephyrus/worktrees/{repo}/{task-slug}/`.

### MCP Server Management

Manage MCP servers available to agents:

```bash
zeph mcp ls                     # list discovered servers (project + user)
zeph mcp add my-tool node ./my-server.js -a --port -a 3000
zeph mcp rm my-tool             # remove a user-level server
```

User-level servers are stored at `~/.zephyrus/mcp/servers.json`. Project-level servers come from the project's `.mcp.json`.

### Layouts

Predefined tmux arrangements:

```bash
zeph layout ls               # list: solo, pair, squad, full
zeph layout apply pair       # 2 agents + nvim + lazygit
```

| Layout | Panes |
|--------|-------|
| `solo` | 1 agent + nvim + lazygit |
| `pair` | 2 agents + nvim + lazygit |
| `squad` | 4 agents + nvim + lazygit |
| `full` | 6 agents (grid) |

### TUI Dashboard

A live terminal dashboard built with Textual:

```bash
zeph-tui                     # launch the dashboard
```

Features: live task table, agent panel, WebSocket event log, keyboard shortcuts (n=new task, d=done, f=fail, x=delete, r=refresh, q=quit).

### tmux Status Line

Add Zephyrus status to your tmux status bar:

```bash
# In tmux.conf:
set -g status-right '#(~/.../bin/zeph-status)'
```

Shows agent counts and task breakdown: `zeph:2w/3a 4p/1r/2d`

### Neovim Integration

Bootstrap automatically symlinks `nvim/` to `~/.config/nvim` and the included `init.lua` auto-detects the nvim-plugin path from the `~/.config/zephyrus` symlink — no manual config needed.

If you use your own `init.lua`, add the plugin to lazy.nvim:

```lua
-- Point at wherever you cloned zephyrus
{ dir = "/path/to/zephyrus/nvim-plugin", lazy = false },
```

Commands:

| Command | Description |
|---------|-------------|
| `:ZephTasks` | Floating task board |
| `:ZephAgents` | Floating agent panel |
| `:ZephPush` | Push a new task |
| `:ZephDiff <id>` | Show diff for a task |
| `:ZephMerge <id>` | Merge a task's branch |
| `:ZephReject <id>` | Reject with feedback |
| `:ZephRefresh` | Refresh cached data |

Statusline integration: `require('zephyrus').status_line()` returns a compact status string.

### MCP Integration (for AI Agents)

The MCP server lets AI agents coordinate through the task stack. When you launch agents via `zeph up`, the daemon auto-injects `.mcp.json` into their working directories.

For manual setup, add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "zephyrus": {
      "command": "/path/to/zephyrus/bin/zeph-mcp",
      "env": {
        "ZEPH_DAEMON_URL": "http://127.0.0.1:9800",
        "ZEPH_AGENT_ID": "claude-1"
      }
    }
  }
}
```

This gives the agent 6 tools:

| Tool | Description |
|------|-------------|
| `zeph_task_push` | Add a new task to the stack |
| `zeph_task_pop` | Claim the next available task |
| `zeph_task_update` | Update current task status |
| `zeph_task_list` | View all tasks |
| `zeph_status` | Report agent status to the daemon |
| `zeph_agent_list` | List all active agents |

Agents can push subtasks for other agents, flag work for review, and report their progress — enabling real coordination, not just parallel isolation.

## Project Structure

```
zephyrus/
├── bin/
│   ├── bootstrap.sh          # Full setup script (--deps for system packages)
│   ├── devinit.sh            # Project scaffolding (python, node, go, etc.)
│   ├── zeph                  # CLI wrapper
│   ├── zephd                 # Daemon wrapper
│   ├── zeph-mcp              # MCP server wrapper
│   ├── zeph-tui              # TUI dashboard wrapper
│   └── zeph-status           # tmux status line script
├── daemon/                   # Coordination daemon (FastAPI + SQLite)
│   ├── pyproject.toml
│   └── zephd/
│       ├── main.py           # API routes + lifecycle
│       ├── models.py         # Task, Agent, Event schemas
│       ├── db.py             # SQLite layer + dependency resolution
│       ├── agent_registry.py # In-memory registry + heartbeat
│       ├── event_bus.py      # WebSocket pub/sub
│       ├── layout_engine.py  # tmux pane management
│       ├── mcp_config.py     # MCP config auto-injection
│       ├── worktree_manager.py # Git worktree lifecycle
│       └── templates.py      # Agent prompt templates
├── cli/                      # CLI (Typer + Rich)
│   ├── pyproject.toml
│   └── zeph/
│       ├── main.py           # Entry point + top-level aliases
│       ├── client.py         # HTTP client for daemon
│       └── commands/
│           ├── tasks.py      # push, ls, show, done, fail, edit, rm
│           ├── agents.py     # ls, launch, stop
│           ├── layout.py     # ls, apply
│           ├── review.py     # diff, merge, reject, review
│           ├── worktree.py   # ls, clean, rm
│           └── mcp.py        # ls, add, rm
├── mcp-server/               # MCP server (JSON-RPC over stdio)
│   ├── pyproject.toml
│   └── zeph_mcp/
│       └── server.py         # 6 tools for agent coordination
├── tui/                      # TUI dashboard (Textual)
│   ├── pyproject.toml
│   └── zeph_tui/
│       └── app.py            # Live dashboard with task/agent panels
├── nvim/                     # Neovim config (symlinked to ~/.config/nvim)
│   └── init.lua              # Full IDE config (LSP, treesitter, etc.)
├── nvim-plugin/              # Neovim plugin (Lua)
│   ├── plugin/
│   │   └── zephyrus.vim      # Command definitions
│   └── lua/zephyrus/
│       ├── init.lua          # Main module (setup, commands, API)
│       └── ui.lua            # Floating windows + highlighting
├── kitty/                    # Kitty terminal config
│   ├── kitty.conf
│   ├── theme.conf
│   └── font.conf
├── tmux/
│   ├── tmux.conf             # tmux config (symlinked to ~/.config/tmux/)
│   ├── bin/                  # Status bar scripts (git, venv, system stats)
│   │   ├── git_branch.sh
│   │   ├── venv_name.sh
│   │   └── system_stats.sh   # macOS + Linux support
│   └── layouts/              # Layout definitions (YAML)
│       ├── solo.yaml
│       ├── pair.yaml
│       ├── squad.yaml
│       └── full.yaml
├── templates/                # Project templates for devinit.sh
├── deps/
│   └── apt-packages.txt      # Linux package list
├── Brewfile                  # macOS dependency manifest
├── docs/
│   └── DESIGN.md             # Full architecture design document
└── LICENSE
```

## Cheatsheets & Overlays

Zephyrus also includes portable terminal tooling:

- **Kitty overlay** — `Ctrl+Shift+H` for a cheat sheet overlay
- **Neovim cheatsheet** — `:ZephyrusCheat` or `<leader>ch`

## Roadmap

See [docs/DESIGN.md](docs/DESIGN.md) for the full architecture design.

- **Phase 1 (done):** Daemon, CLI, MCP server, tmux layouts
- **Phase 2 (done):** MCP config auto-injection, server discovery, agent prompt templates, tmux status line
- **Phase 3 (done):** Git worktree manager, review/merge/reject workflow, CLI commands for all new features
- **Phase 4 (done):** TUI dashboard (Textual), Neovim plugin, updated README

**Up next:** CI/CD feedback loop, intelligent merge orchestration, persistent agent memory, auto-decomposition with dependency graphs.

## License

MIT — see [LICENSE](LICENSE).
