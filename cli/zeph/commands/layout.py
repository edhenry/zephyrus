"""Layout and session lifecycle commands."""

from __future__ import annotations

from typing import Optional

import typer
from rich.console import Console

from ..client import ZephClient

app = typer.Typer(help="Manage layouts and sessions")
console = Console()


@app.command("ls")
def ls():
    """List available layouts."""
    client = ZephClient()
    data = client.get_layouts()
    layouts = data.get("layouts", [])

    if not layouts:
        console.print("[dim]No layouts found.[/dim]")
        return

    console.print("[bold]Available layouts:[/bold]")
    for name in layouts:
        console.print(f"  - {name}")


@app.command("apply")
def apply(
    name: str = typer.Argument(..., help="Layout name"),
    project_path: str = typer.Option(".", "-p", "--project", help="Project path"),
):
    """Apply a layout to the tmux session."""
    client = ZephClient()
    result = client.apply_layout(name, project_path)
    console.print(f"[green]Applied layout[/green] {result.get('layout', name)}")

    agents = result.get("agents", [])
    if agents:
        console.print(f"  Launched {len(agents)} agent(s):")
        for a in agents:
            console.print(f"    - {a['name']} ({a['mode']})")
