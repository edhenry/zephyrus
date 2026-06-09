"""Git worktree management commands."""

from __future__ import annotations

from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

from ..client import ZephClient

app = typer.Typer(help="Manage git worktrees")
console = Console()


@app.command("ls")
def ls(
    project_path: str = typer.Option(".", "-p", "--project", help="Project path"),
):
    """List all git worktrees."""
    client = ZephClient()
    data = client.list_worktrees(project_path)
    worktrees = data.get("worktrees", [])

    if not worktrees:
        console.print("[dim]No worktrees.[/dim]")
        return

    table = Table(show_header=True, header_style="bold")
    table.add_column("Branch", min_width=20)
    table.add_column("Path", min_width=30)
    table.add_column("HEAD", width=10)
    table.add_column("Flags", width=10)

    for wt in worktrees:
        flags = []
        if wt.get("bare"):
            flags.append("bare")
        if wt.get("detached"):
            flags.append("detached")

        table.add_row(
            f"[cyan]{wt.get('branch', 'n/a')}[/cyan]",
            wt.get("path", ""),
            wt.get("head", "")[:10] if wt.get("head") else "",
            " ".join(flags) if flags else "",
        )

    console.print(table)


@app.command("clean")
def clean(
    project_path: str = typer.Option(".", "-p", "--project", help="Project path"),
):
    """Remove stale worktrees for merged/deleted branches."""
    client = ZephClient()
    result = client.clean_worktrees(project_path)
    count = result.get("count", 0)

    if count == 0:
        console.print("[dim]No stale worktrees to clean.[/dim]")
    else:
        console.print(f"[green]Cleaned {count} stale worktree(s):[/green]")
        for path in result.get("cleaned", []):
            console.print(f"  - {path}")


@app.command("rm")
def rm(
    worktree_path: str = typer.Argument(..., help="Path of the worktree to remove"),
    project_path: str = typer.Option(".", "-p", "--project", help="Project path"),
):
    """Remove a specific worktree."""
    client = ZephClient()
    client.remove_worktree(project_path, worktree_path)
    console.print(f"[red]Removed[/red] worktree at {worktree_path}")
