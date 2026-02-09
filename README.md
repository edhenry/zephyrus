# Zephyrus — Coding Agent Command Center

A terminal-native multi-agent orchestration environment. Push tasks to a shared stack, launch AI coding agents that claim and execute work, review changes in Neovim, and merge — all from tmux.

Agents coordinate through a shared task stack with priority ordering and dependency resolution. They can push subtasks for each other, report status, and flag work for human review — all via MCP tools.

## Quick Start

```bash
git clone <repo-url> ~/zephyrus   # clone anywhere you like
cd ~/zephyrus
./bin/bootstrap.sh                 # creates venv, installs packages
source .venv/bin/activate          # activate the environment
```

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
                    │  WebSocket   │
                    │  SQLite DB   │
                    │  Task Stack  │
                    │  Agent Reg.  │
                    └──────────────┘
```

- **zephd** — FastAPI coordination daemon. Task stack with SQLite persistence, in-memory agent registry with heartbeat monitoring, WebSocket event bus, tmux layout engine. Runs on port 9800.
- **zeph** — CLI for humans. Push/pop tasks, launch agents, apply layouts, manage lifecycle.
- **zeph-mcp** — MCP server (JSON-RPC over stdio). Gives AI agents 6 tools to interact with the task stack. Works with Claude Code, Gemini CLI, or any MCP-compatible agent.

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

### MCP Integration (for AI Agents)

The MCP server lets AI agents coordinate through the task stack. Add to your project's `.mcp.json`:

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
│   ├── bootstrap.sh          # Install script (auto-detects repo location)
│   ├── devinit.sh            # Polyglot project scaffolder
│   ├── zeph                  # CLI wrapper
│   ├── zephd                 # Daemon wrapper
│   └── zeph-mcp              # MCP server wrapper
├── daemon/                   # Coordination daemon (FastAPI + SQLite)
│   ├── pyproject.toml
│   └── zephd/
│       ├── main.py           # API routes + lifecycle
│       ├── models.py         # Task, Agent, Event schemas
│       ├── db.py             # SQLite layer + dependency resolution
│       ├── agent_registry.py # In-memory registry + heartbeat
│       ├── event_bus.py      # WebSocket pub/sub
│       └── layout_engine.py  # tmux pane management
├── cli/                      # CLI (Typer + Rich)
│   ├── pyproject.toml
│   └── zeph/
│       ├── main.py           # Entry point + top-level aliases
│       ├── client.py         # HTTP client for daemon
│       └── commands/
│           ├── tasks.py      # push, ls, show, done, fail, edit, rm
│           ├── agents.py     # ls, launch, stop
│           └── layout.py     # ls, apply
├── mcp-server/               # MCP server (JSON-RPC over stdio)
│   ├── pyproject.toml
│   └── zeph_mcp/
│       └── server.py         # 6 tools for agent coordination
├── tmux/
│   ├── tmux.conf             # tmux configuration
│   └── layouts/              # Layout definitions (YAML)
│       ├── solo.yaml
│       ├── pair.yaml
│       ├── squad.yaml
│       └── full.yaml
├── kitty/                    # Kitty terminal config
├── nvim/                     # Neovim config (init.lua)
├── zephyrus/                 # Core assets (cheatsheets, overlays, branding)
├── docs/
│   └── DESIGN.md             # Full architecture design document
└── LICENSE
```

## Cheatsheets & Overlays

Zephyrus also includes portable terminal tooling:

- **Kitty overlay** — `Ctrl+Shift+H` for a cheat sheet overlay
- **Neovim plugin** — `:ZephyrusCheat` or `<leader>ch` for a floating cheat sheet
- **Dark/Light themes** — auto-detected

```bash
# Kitty — add to kitty.conf:
map ctrl+shift+h launch --type=overlay --title "Zephyrus Cheats" --cwd=current --env ZE_CHALK=1 sh -lc "~/.config/zephyrus/overlays/kitty/cheat_overlay.sh"

# Neovim — add to lazy.nvim:
{ dir = vim.fn.expand("~/.config/zephyrus/nvim"), lazy = false },
```

## Roadmap

See [docs/DESIGN.md](docs/DESIGN.md) for the full architecture design.

**Phase 1 (done):** Daemon, CLI, MCP server, tmux layouts
**Phase 2 (next):** MCP config auto-injection, server discovery, tmux status line
**Phase 3:** Git worktree manager, review/merge workflow, Neovim plugin
**Phase 4:** TUI dashboard (Textual), session persistence, agent templates

## License

MIT — see [LICENSE](LICENSE).
