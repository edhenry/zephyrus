"""Zephyrus Command Center TUI dashboard.

A full-featured terminal UI for monitoring and controlling multi-agent
coding sessions.  Connects to the zephd FastAPI daemon for data and
receives real-time events over a WebSocket.

Usage:
    zeph-tui                       # uses default http://127.0.0.1:9800
    ZEPH_DAEMON_URL=http://host:port zeph-tui
"""

from __future__ import annotations

import json
import os
import asyncio
from datetime import datetime, timezone

import httpx
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Header,
    Input,
    Label,
    RichLog,
    Select,
    Static,
)
from textual import work

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DAEMON_URL = os.environ.get("ZEPH_DAEMON_URL", "http://127.0.0.1:9800")
WS_URL = DAEMON_URL.replace("http://", "ws://").replace("https://", "wss://") + "/ws"

# ---------------------------------------------------------------------------
# Visual style maps
# ---------------------------------------------------------------------------

TASK_STATUS_STYLES: dict[str, tuple[str, str]] = {
    "pending": ("\u25cb", "white"),       # ○
    "claimed": ("\u25c9", "cyan"),        # ◉
    "in_progress": ("\u25cd", "yellow"),  # ◍
    "in_review": ("\u25c8", "magenta"),   # ◈
    "done": ("\u25cf", "green"),          # ●
    "failed": ("\u2717", "red"),          # ✗
    "blocked": ("\u2298", "red"),         # ⊘
}

AGENT_STATUS_STYLES: dict[str, tuple[str, str]] = {
    "starting": ("\u25cc", "cyan"),       # ◌
    "idle": ("\u25cb", "white"),          # ○
    "working": ("\u25cd", "yellow"),      # ◍
    "waiting": ("\u25c8", "magenta"),     # ◈
    "done": ("\u25cf", "green"),          # ●
    "error": ("\u2717", "red"),           # ✗
}

# Priority is an integer 0-9 in the daemon (0 = highest).
PRIORITY_LABELS: dict[int, tuple[str, str]] = {
    0: ("crit", "red bold"),
    1: ("crit", "red bold"),
    2: ("high", "red"),
    3: ("high", "red"),
    4: ("med", "yellow"),
    5: ("med", "yellow"),
    6: ("low", "green"),
    7: ("low", "green"),
    8: ("bg", "dim"),
    9: ("bg", "dim"),
}

# Named priorities offered in the "new task" dialog, mapped to integer values.
NAMED_PRIORITIES: list[tuple[str, int]] = [
    ("Critical", 1),
    ("High", 3),
    ("Medium", 5),
    ("Low", 7),
    ("Background", 9),
]


def _priority_label(value: int) -> tuple[str, str]:
    """Return (short_label, rich_color) for a numeric priority."""
    return PRIORITY_LABELS.get(value, ("med", "yellow"))


# ===================================================================
# New Task modal screen
# ===================================================================


class NewTaskScreen(ModalScreen[dict | None]):
    """Modal dialog for creating a new task."""

    CSS = """
    NewTaskScreen {
        align: center middle;
    }

    #new-task-dialog {
        width: 64;
        height: auto;
        max-height: 24;
        border: thick $accent;
        background: $surface;
        padding: 1 2;
    }

    #dialog-title {
        text-style: bold;
        width: 100%;
        content-align: center middle;
        margin-bottom: 1;
    }

    .field-label {
        margin-top: 1;
    }

    #new-task-dialog Input {
        margin-bottom: 1;
    }

    #new-task-dialog Select {
        margin-bottom: 1;
    }

    #button-row {
        height: 3;
        align: center middle;
        margin-top: 1;
    }

    #button-row Button {
        margin: 0 1;
    }
    """

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def compose(self) -> ComposeResult:
        with Vertical(id="new-task-dialog"):
            yield Label("Create New Task", id="dialog-title")
            yield Label("Title:", classes="field-label")
            yield Input(placeholder="Enter task title...", id="task-title")
            yield Label("Description:", classes="field-label")
            yield Input(placeholder="Enter task description (optional)...", id="task-description")
            yield Label("Priority:", classes="field-label")
            yield Select(
                NAMED_PRIORITIES,
                value=5,
                id="task-priority",
                allow_blank=False,
            )
            with Horizontal(id="button-row"):
                yield Button("Create", variant="primary", id="create-btn")
                yield Button("Cancel", variant="default", id="cancel-btn")

    def on_mount(self) -> None:
        self.query_one("#task-title", Input).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "create-btn":
            self._submit()
        elif event.button.id == "cancel-btn":
            self.dismiss(None)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Pressing Enter inside an input triggers submission."""
        self._submit()

    def _submit(self) -> None:
        title = self.query_one("#task-title", Input).value.strip()
        if not title:
            self.query_one("#task-title", Input).focus()
            return
        description = self.query_one("#task-description", Input).value.strip()
        priority_select = self.query_one("#task-priority", Select)
        priority = priority_select.value if priority_select.value is not Select.BLANK else 5
        self.dismiss({
            "title": title,
            "description": description,
            "priority": priority,
        })

    def action_cancel(self) -> None:
        self.dismiss(None)


# ===================================================================
# Status bar widget
# ===================================================================


class StatusBar(Static):
    """Compact status bar showing daemon connection state and summary counts."""

    DEFAULT_CSS = """
    StatusBar {
        height: 1;
        background: $boost;
        color: $text;
        padding: 0 1;
    }
    """

    def __init__(self, **kwargs) -> None:
        super().__init__("Connecting to daemon...", **kwargs)

    def set_status(self, status: dict | None) -> None:
        if status is None:
            self.update(
                f"[bold red]\u25cf Daemon offline[/]  |  "
                f"Cannot reach [underline]{DAEMON_URL}[/underline]"
            )
            return
        agents = status.get("agents", {})
        tasks = status.get("tasks", {})
        parts = [
            "[bold green]\u25cf Online[/]",
            (
                f"Agents: [cyan]{agents.get('total', 0)}[/] "
                f"([yellow]{agents.get('working', 0)}W[/] "
                f"[white]{agents.get('idle', 0)}I[/] "
                f"[red]{agents.get('error', 0)}E[/])"
            ),
            (
                f"Tasks: [cyan]{tasks.get('total', 0)}[/] "
                f"([yellow]{tasks.get('in_progress', 0)}A[/] "
                f"[white]{tasks.get('pending', 0)}P[/] "
                f"[green]{tasks.get('done', 0)}D[/] "
                f"[red]{tasks.get('failed', 0)}F[/])"
            ),
        ]
        self.update("  |  ".join(parts))


# ===================================================================
# Main dashboard application
# ===================================================================


class ZephDashboard(App):
    """Zephyrus Command Center TUI dashboard."""

    TITLE = "Zephyrus Command Center"

    CSS = """
    #status-bar {
        dock: top;
        height: 1;
    }

    #main-area {
        height: 1fr;
    }

    #task-panel {
        width: 3fr;
        border: solid $primary;
    }

    #task-panel-title {
        height: 1;
        background: $primary;
        color: $text;
        padding: 0 1;
        text-style: bold;
    }

    #agent-panel {
        width: 2fr;
        border: solid $secondary;
    }

    #agent-panel-title {
        height: 1;
        background: $secondary;
        color: $text;
        padding: 0 1;
        text-style: bold;
    }

    #log-panel {
        height: 12;
        border: solid $accent;
    }

    #log-panel-title {
        height: 1;
        background: $accent;
        color: $text;
        padding: 0 1;
        text-style: bold;
    }

    DataTable {
        height: 1fr;
    }

    RichLog {
        height: 1fr;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("n", "new_task", "New Task", priority=True),
        Binding("r", "refresh", "Refresh"),
        Binding("d", "mark_done", "Done"),
        Binding("f", "mark_failed", "Fail"),
        Binding("x", "delete_task", "Delete"),
        Binding("tab", "focus_next", "Next Panel", show=False),
        Binding("shift+tab", "focus_previous", "Prev Panel", show=False),
    ]

    def __init__(self) -> None:
        super().__init__()
        self._tasks: list[dict] = []
        self._agents: list[dict] = []

    # ---------------------------------------------------------------
    # Layout
    # ---------------------------------------------------------------

    def compose(self) -> ComposeResult:
        yield Header()
        yield StatusBar(id="status-bar")
        with Horizontal(id="main-area"):
            with Vertical(id="task-panel"):
                yield Static("Tasks", id="task-panel-title")
                yield DataTable(id="task-table")
            with Vertical(id="agent-panel"):
                yield Static("Agents", id="agent-panel-title")
                yield DataTable(id="agent-table")
        with Vertical(id="log-panel"):
            yield Static("Event Log", id="log-panel-title")
            yield RichLog(id="event-log", highlight=True, markup=True)
        yield Footer()

    def on_mount(self) -> None:
        # -- Task table setup --
        task_table = self.query_one("#task-table", DataTable)
        task_table.add_columns("", "ID", "Pri", "Title", "Status", "Agent")
        task_table.cursor_type = "row"
        task_table.zebra_stripes = True

        # -- Agent table setup --
        agent_table = self.query_one("#agent-table", DataTable)
        agent_table.add_columns("", "Name", "Mode", "Status", "Task", "Pane")
        agent_table.cursor_type = "row"
        agent_table.zebra_stripes = True

        # -- Event log bootstrap --
        event_log = self.query_one("#event-log", RichLog)
        event_log.write(f"[dim]Zephyrus Command Center starting...[/]")
        event_log.write(f"[dim]Daemon URL: {DAEMON_URL}[/]")
        event_log.write(f"[dim]WebSocket:  {WS_URL}[/]")

        # -- Kick off background workers --
        self.refresh_data()
        self.set_interval(3.0, self.refresh_data)
        self._connect_websocket()

    # ---------------------------------------------------------------
    # HTTP helpers
    # ---------------------------------------------------------------

    async def _fetch(self, path: str) -> dict | list | None:
        """GET a JSON resource from the daemon. Returns None on failure."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{DAEMON_URL}{path}")
                resp.raise_for_status()
                return resp.json()
        except Exception:
            return None

    async def _post(
        self,
        path: str,
        data: dict | None = None,
        params: dict | None = None,
    ) -> dict | None:
        """POST to the daemon. Returns parsed JSON or None on failure."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.post(
                    f"{DAEMON_URL}{path}", json=data, params=params,
                )
                resp.raise_for_status()
                return resp.json()
        except Exception:
            return None

    async def _patch(self, path: str, data: dict) -> dict | None:
        """PATCH a daemon resource. Returns parsed JSON or None on failure."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.patch(f"{DAEMON_URL}{path}", json=data)
                resp.raise_for_status()
                return resp.json()
        except Exception:
            return None

    async def _delete(self, path: str) -> dict | None:
        """DELETE a daemon resource. Returns parsed JSON or None on failure."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.delete(f"{DAEMON_URL}{path}")
                resp.raise_for_status()
                return resp.json()
        except Exception:
            return None

    # ---------------------------------------------------------------
    # Data refresh (polling)
    # ---------------------------------------------------------------

    @work(exclusive=True, group="refresh")
    async def refresh_data(self) -> None:
        """Fetch /status, /tasks, /agents concurrently and update the UI."""
        status, tasks, agents = await asyncio.gather(
            self._fetch("/status"),
            self._fetch("/tasks"),
            self._fetch("/agents"),
        )
        self.query_one("#status-bar", StatusBar).set_status(status)
        if tasks is not None:
            self._tasks = tasks
            self._rebuild_task_table()
        if agents is not None:
            self._agents = agents
            self._rebuild_agent_table()

    # ---------------------------------------------------------------
    # Table rebuilders
    # ---------------------------------------------------------------

    def _rebuild_task_table(self) -> None:
        table = self.query_one("#task-table", DataTable)
        table.clear()
        for task in self._tasks:
            status = task.get("status", "pending")
            icon, color = TASK_STATUS_STYLES.get(status, ("?", "white"))

            task_id = str(task.get("id", ""))[:12]

            raw_pri = task.get("priority", 5)
            pri_label, pri_color = _priority_label(
                raw_pri if isinstance(raw_pri, int) else 5
            )

            title = task.get("title", "Untitled")
            if len(title) > 44:
                title = title[:41] + "..."

            assigned = task.get("assigned_to") or ""
            if len(assigned) > 14:
                assigned = assigned[:11] + "..."

            table.add_row(
                f"[{color}]{icon}[/]",
                f"[dim]{task_id}[/]",
                f"[{pri_color}]{pri_label}[/]",
                title,
                f"[{color}]{status}[/]",
                assigned if assigned else "[dim]--[/]",
                key=str(task.get("id", "")),
            )

    def _rebuild_agent_table(self) -> None:
        table = self.query_one("#agent-table", DataTable)
        table.clear()
        for agent in self._agents:
            status = agent.get("status", "idle")
            icon, color = AGENT_STATUS_STYLES.get(status, ("?", "white"))

            name = agent.get("name", "unknown")
            mode = agent.get("mode", "")

            current_task = agent.get("current_task") or ""
            if len(current_task) > 12:
                current_task = current_task[:12]

            pane = agent.get("tmux_pane") or ""

            table.add_row(
                f"[{color}]{icon}[/]",
                name,
                mode if mode else "[dim]--[/]",
                f"[{color}]{status}[/]",
                current_task if current_task else "[dim]--[/]",
                pane if pane else "[dim]--[/]",
                key=str(agent.get("id", "")),
            )

    # ---------------------------------------------------------------
    # WebSocket event stream
    # ---------------------------------------------------------------

    @work(exclusive=True, group="websocket")
    async def _connect_websocket(self) -> None:
        """Long-running worker that streams events from the daemon WS."""
        import websockets
        import websockets.exceptions

        event_log = self.query_one("#event-log", RichLog)

        while True:
            try:
                async with websockets.connect(WS_URL) as ws:
                    event_log.write("[green]WebSocket connected[/]")
                    async for raw_message in ws:
                        try:
                            event = json.loads(raw_message)
                            self._log_event(event)
                        except json.JSONDecodeError:
                            event_log.write(f"[dim]{raw_message}[/]")
            except asyncio.CancelledError:
                event_log.write("[dim]WebSocket worker cancelled[/]")
                return
            except Exception as exc:
                short = str(exc)[:80]
                event_log.write(
                    f"[red]WS disconnected:[/] [dim]{short}[/] — retry in 5s"
                )
                try:
                    await asyncio.sleep(5)
                except asyncio.CancelledError:
                    return

    def _log_event(self, event: dict) -> None:
        """Format and append a single event to the event log."""
        event_log = self.query_one("#event-log", RichLog)

        raw_ts = event.get("timestamp", "")
        if raw_ts:
            try:
                dt = datetime.fromisoformat(raw_ts)
                ts = dt.strftime("%H:%M:%S")
            except (ValueError, TypeError):
                ts = str(raw_ts)[:8]
        else:
            ts = datetime.now(timezone.utc).strftime("%H:%M:%S")

        etype = event.get("type", "unknown")
        data = event.get("data", {})

        etype_colors = {
            "task.created": "green",
            "task.updated": "yellow",
            "task.completed": "green bold",
            "task.claimed": "cyan",
            "task.failed": "red bold",
            "task.rejected": "red",
            "task.assigned": "cyan",
            "agent.started": "cyan",
            "agent.stopped": "red",
            "agent.status": "yellow",
            "agent.heartbeat": "dim",
        }
        color = etype_colors.get(etype, "white")

        detail = ""
        if isinstance(data, dict):
            for key in ("title", "name", "reason", "message"):
                if key in data and data[key]:
                    val = str(data[key])
                    if len(val) > 60:
                        val = val[:57] + "..."
                    detail = f" -- {val}"
                    break
            if not detail and "task_id" in data:
                detail = f" -- task:{str(data['task_id'])[:12]}"
            if not detail and "agent_id" in data:
                detail = f" -- agent:{str(data['agent_id'])[:12]}"

        event_log.write(f"[dim]{ts}[/] [{color}]{etype}[/]{detail}")

        # Auto-refresh data tables when a meaningful event arrives
        if etype not in ("agent.heartbeat",):
            self.refresh_data()

    # ---------------------------------------------------------------
    # Selected-task helper
    # ---------------------------------------------------------------

    def _selected_task_id(self) -> str | None:
        """Return the task ID of the currently highlighted row, or None."""
        table = self.query_one("#task-table", DataTable)
        if table.row_count == 0:
            return None
        try:
            cell_key = table.coordinate_to_cell_key(table.cursor_coordinate)
            row_key = cell_key.row_key
            return str(row_key.value) if row_key.value else None
        except Exception:
            return None

    # ---------------------------------------------------------------
    # Key-bound actions
    # ---------------------------------------------------------------

    def action_new_task(self) -> None:
        """Push the new-task modal and POST to the daemon on submit."""
        self.push_screen(NewTaskScreen(), callback=self._on_new_task_result)

    @work(exclusive=True)
    async def _on_new_task_result(self, result: dict | None) -> None:
        """Handle the result from the new-task modal."""
        if result is None:
            return

        payload = {
            "title": result["title"],
            "description": result.get("description", ""),
            "priority": result.get("priority", 5),
            "tags": [],
            "depends_on": [],
            "created_by": "tui",
        }
        resp = await self._post("/tasks", data=payload)
        event_log = self.query_one("#event-log", RichLog)
        if resp:
            event_log.write(
                f"[green]Created task:[/] {resp.get('title', '')} "
                f"[dim]({str(resp.get('id', ''))[:12]})[/]"
            )
            self.refresh_data()
        else:
            event_log.write("[red]Failed to create task -- is daemon running?[/]")

    async def action_mark_done(self) -> None:
        """Mark the selected task as done via POST /tasks/{id}/complete."""
        task_id = self._selected_task_id()
        if not task_id:
            return
        resp = await self._post(
            f"/tasks/{task_id}/complete",
            params={"output": "Completed via TUI"},
        )
        event_log = self.query_one("#event-log", RichLog)
        if resp:
            event_log.write(f"[green]Task {task_id[:12]} marked done[/]")
            self.refresh_data()
        else:
            event_log.write(f"[red]Failed to complete task {task_id[:12]}[/]")

    async def action_mark_failed(self) -> None:
        """Mark the selected task as failed via POST /tasks/{id}/fail."""
        task_id = self._selected_task_id()
        if not task_id:
            return
        resp = await self._post(
            f"/tasks/{task_id}/fail",
            params={"reason": "Marked failed via TUI"},
        )
        event_log = self.query_one("#event-log", RichLog)
        if resp:
            event_log.write(f"[yellow]Task {task_id[:12]} marked failed[/]")
            self.refresh_data()
        else:
            event_log.write(f"[red]Failed to update task {task_id[:12]}[/]")

    async def action_delete_task(self) -> None:
        """Delete the selected task via DELETE /tasks/{id}."""
        task_id = self._selected_task_id()
        if not task_id:
            return
        resp = await self._delete(f"/tasks/{task_id}")
        event_log = self.query_one("#event-log", RichLog)
        if resp:
            event_log.write(f"[red]Task {task_id[:12]} deleted[/]")
            self.refresh_data()
        else:
            event_log.write(f"[red]Failed to delete task {task_id[:12]}[/]")

    def action_refresh(self) -> None:
        """Manual refresh triggered by 'r' key."""
        self.refresh_data()
        event_log = self.query_one("#event-log", RichLog)
        event_log.write("[dim]Manual refresh...[/]")


# ===================================================================
# Entry point
# ===================================================================


def main() -> None:
    app = ZephDashboard()
    app.run()


if __name__ == "__main__":
    main()
