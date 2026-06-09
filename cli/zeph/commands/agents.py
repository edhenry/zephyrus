"""Agent management commands."""

from __future__ import annotations

from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

from ..client import ZephClient

app = typer.Typer(help="Manage agents")
console = Console()

STATUS_COLORS = {
    "starting": "cyan",
    "idle": "white",
    "working": "yellow",
    "waiting": "magenta",
    "done": "green",
    "error": "red",
}

STATUS_ICONS = {
    "starting": ".",
    "idle": "-",
    "working": "~",
    "waiting": "?",
    "done": "+",
    "error": "x",
}


@app.command("ls")
def ls():
    """List all active agents."""
    client = ZephClient()
    agents = client.list_agents()

    if not agents:
        console.print("[dim]No agents running.[/dim]")
        return

    table = Table(show_header=True, header_style="bold")
    table.add_column("", width=1)
    table.add_column("Name", min_width=12)
    table.add_column("Mode", width=8)
    table.add_column("Status", width=10)
    table.add_column("Task", width=14)
    table.add_column("Pane", width=10)
    table.add_column("PID", width=8)

    for a in agents:
        st = a["status"]
        color = STATUS_COLORS.get(st, "white")
        icon = STATUS_ICONS.get(st, " ")
        task = a.get("current_task", "") or ""
        if task and len(task) > 14:
            task = task[:14]

        table.add_row(
            f"[{color}]{icon}[/{color}]",
            a["name"],
            a["mode"],
            f"[{color}]{st}[/{color}]",
            task,
            a.get("tmux_pane", "") or "",
            str(a.get("pid", "")) or "",
        )

    console.print(table)


@app.command("launch")
def launch(
    mode: str = typer.Argument("claude", help="Agent mode (claude, gemini, codex, aider, shell)"),
    name: Optional[str] = typer.Option(None, "-n", "--name", help="Agent name"),
    project_path: str = typer.Option(".", "-p", "--project", help="Project path"),
):
    """Launch a new agent."""
    client = ZephClient()

    if not name:
        agents = client.list_agents()
        count = sum(1 for a in agents if a["mode"] == mode) + 1
        name = f"{mode}-{count}"

    agent = client.register_agent(name, mode, project_path)
    console.print(f"[green]Launched[/green] {agent['name']} (id={agent['id'][:12]}, mode={agent['mode']})")


@app.command("stop")
def stop(
    name: str = typer.Argument(..., help="Agent name or ID"),
    all_agents: bool = typer.Option(False, "--all", help="Stop all agents"),
):
    """Stop an agent."""
    client = ZephClient()

    if all_agents:
        agents = client.list_agents()
        for a in agents:
            client.deregister_agent(a["id"])
            console.print(f"[red]Stopped[/red] {a['name']}")
        return

    agents = client.list_agents()
    match = _find_agent(agents, name)
    if not match:
        console.print(f"[red]Agent not found: {name}[/red]")
        raise typer.Exit(1)

    client.deregister_agent(match["id"])
    console.print(f"[red]Stopped[/red] {match['name']}")


def _find_agent(agents: list[dict], name_or_id: str) -> dict | None:
    """Find an agent by name or ID prefix."""
    for a in agents:
        if a["name"] == name_or_id or a["id"].startswith(name_or_id):
            return a
    return None
