"""Zephyrus Command Center CLI — main entry point."""

from __future__ import annotations

import os
import subprocess
import sys
import time

import typer
from rich.console import Console

from .client import ZephClient
from .commands import agents, layout, tasks

console = Console()

app = typer.Typer(
    name="zeph",
    help="Zephyrus Command Center — multi-agent orchestration for terminal-native development",
    no_args_is_help=True,
)

# Register subcommands
app.add_typer(tasks.app, name="task", help="Manage the task stack")
app.add_typer(agents.app, name="agent", help="Manage agents")
app.add_typer(layout.app, name="layout", help="Manage layouts")


# ============================================================
# Top-level convenience aliases
# ============================================================


@app.command()
def push(
    title: str = typer.Argument(..., help="Task title"),
    description: str = typer.Option("", "-d", "--desc"),
    priority: int = typer.Option(5, "-p", "--priority", min=0, max=9),
    tags: list[str] | None = typer.Option(None, "-t", "--tag"),
):
    """Push a task onto the stack (shortcut for 'task push')."""
    client = ZephClient()
    task = client.push_task(title, description, priority, tags=tags)
    console.print(f"[green]Created task[/green] {task['id'][:12]} — {task['title']}")


@app.command("ls")
def ls(
    status: str | None = typer.Option(None, "-s", "--status"),
    tag: str | None = typer.Option(None, "-t", "--tag"),
    all_tasks: bool = typer.Option(False, "--all"),
):
    """List tasks (shortcut for 'task ls')."""
    client = ZephClient()
    task_list = client.list_tasks(status=status, tag=tag)
    if not all_tasks and not status:
        task_list = [t for t in task_list if t["status"] not in ("done", "failed")]

    if not task_list:
        console.print("[dim]No tasks.[/dim]")
        return

    from .commands.tasks import STATUS_COLORS, STATUS_ICONS
    from rich.table import Table

    table = Table(show_header=True, header_style="bold")
    table.add_column("", width=1)
    table.add_column("ID", width=12)
    table.add_column("P", width=2, justify="center")
    table.add_column("Title", min_width=20)
    table.add_column("Status", width=12)
    table.add_column("Agent", width=12)

    for t in task_list:
        st = t["status"]
        color = STATUS_COLORS.get(st, "white")
        icon = STATUS_ICONS.get(st, " ")
        agent = t.get("assigned_to", "") or ""
        if agent and len(agent) > 12:
            agent = agent[:12]

        table.add_row(
            f"[{color}]{icon}[/{color}]",
            t["id"][:12],
            str(t["priority"]),
            t["title"],
            f"[{color}]{st}[/{color}]",
            agent,
        )

    console.print(table)


@app.command()
def agents_cmd():
    """List agents (shortcut for 'agent ls')."""
    agents.ls()


# Rename for typer
agents_cmd.__name__ = "agents"


@app.command()
def status():
    """Show command center status."""
    client = ZephClient()
    data = client.status()

    console.print("\n[bold]Zephyrus Command Center[/bold]")
    console.print(f"  Daemon:  [green]running[/green] (port {data['port']}, pid {data['pid']})")
    console.print(f"  Agents:  {data['agents']}")

    t = data["tasks"]
    console.print(
        f"  Tasks:   {t['total']} total"
        f" ({t['pending']} pending, {t['in_progress']} active,"
        f" {t['in_review']} review, {t['done']} done, {t['failed']} failed)"
    )
    console.print()


@app.command()
def up(
    project_path: str = typer.Option(".", "-p", "--project", help="Project path"),
    layout_name: str = typer.Option("solo", "-l", "--layout", help="Layout to apply"),
    agents_count: int = typer.Option(0, "-a", "--agents", help="Number of agents (overrides layout)"),
):
    """Start the command center — daemon + tmux layout + agents."""
    # Start daemon if not running
    if not _daemon_is_running():
        console.print("[yellow]Starting zephd...[/yellow]")
        _start_daemon()
        time.sleep(1.5)

        if not _daemon_is_running():
            console.print("[red]Failed to start daemon.[/red]")
            raise typer.Exit(1)

    client = ZephClient()
    result = client.session_up(project_path, layout_name)
    console.print(f"[green]Command center is up[/green] (layout={layout_name})")

    launched = result.get("agents", [])
    if launched:
        console.print(f"  {len(launched)} agent(s) launched")
        for a in launched:
            console.print(f"    - {a['name']} ({a['mode']})")


@app.command()
def down():
    """Shut down the command center."""
    if _daemon_is_running():
        client = ZephClient()
        try:
            client.session_down()
        except SystemExit:
            pass
        _stop_daemon()
        console.print("[red]Command center stopped.[/red]")
    else:
        console.print("[dim]Daemon is not running.[/dim]")


# ============================================================
# Daemon management helpers
# ============================================================


def _pid_file():
    from pathlib import Path
    return Path.home() / ".zephyrus" / "state" / "zephd.pid"


def _daemon_is_running() -> bool:
    pid_file = _pid_file()
    if not pid_file.exists():
        return False
    try:
        pid = int(pid_file.read_text().strip())
        os.kill(pid, 0)
        return True
    except (ValueError, ProcessLookupError, PermissionError):
        pid_file.unlink(missing_ok=True)
        return False


def _start_daemon() -> None:
    log_dir = _pid_file().parent
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "zephd.log"

    with open(log_file, "a") as lf:
        subprocess.Popen(
            [sys.executable, "-m", "zephd.main"],
            stdout=lf,
            stderr=lf,
            start_new_session=True,
        )


def _stop_daemon() -> None:
    import signal

    pid_file = _pid_file()
    if pid_file.exists():
        try:
            pid = int(pid_file.read_text().strip())
            os.kill(pid, signal.SIGTERM)
        except (ValueError, ProcessLookupError):
            pass
        pid_file.unlink(missing_ok=True)


def main():
    app()


if __name__ == "__main__":
    main()
