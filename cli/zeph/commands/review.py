"""Review, merge, and reject workflow commands."""

from __future__ import annotations

from typing import Optional

import typer
from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax
from rich.table import Table

from ..client import ZephClient

app = typer.Typer(help="Review agent work — diff, merge, reject")
console = Console()


def _find_task(tasks: list[dict], prefix: str) -> dict | None:
    for t in tasks:
        if t["id"].startswith(prefix) or t["id"][:12].startswith(prefix):
            return t
    return None


@app.command("diff")
def diff(
    task_id: str = typer.Argument(..., help="Task ID (prefix match)"),
    project_path: str = typer.Option(".", "-p", "--project"),
):
    """Show diff summary for a task's branch."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    data = client.task_diff(match["id"], project_path)

    console.print(f"\n[bold]Diff for task[/bold] {match['id'][:12]} — {match['title']}")
    console.print(f"  Branch: [cyan]{data['branch']}[/cyan] vs [cyan]{data['base']}[/cyan]\n")

    # File list
    files = data.get("files", [])
    if files:
        table = Table(show_header=True, header_style="bold")
        table.add_column("Status", width=3)
        table.add_column("File", min_width=30)

        status_colors = {"A": "green", "M": "yellow", "D": "red", "R": "cyan"}
        for f in files:
            st = f["status"]
            color = status_colors.get(st, "white")
            table.add_row(f"[{color}]{st}[/{color}]", f["path"])

        console.print(table)

    if data.get("shortstat"):
        console.print(f"\n  {data['shortstat']}")
    console.print()


@app.command("merge")
def merge(
    task_id: str = typer.Argument(..., help="Task ID (prefix match)"),
    project_path: str = typer.Option(".", "-p", "--project"),
    target: str = typer.Option("main", "-t", "--target", help="Target branch"),
    yes: bool = typer.Option(False, "-y", "--yes", help="Skip confirmation"),
):
    """Merge a task's branch into the target branch."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    if not yes:
        console.print(f"Merging [cyan]{match.get('branch', 'unknown')}[/cyan] into [cyan]{target}[/cyan]")
        confirm = typer.confirm("Proceed?")
        if not confirm:
            raise typer.Exit(0)

    result = client.merge_task(match["id"], project_path, target)
    console.print(f"[green]Merged[/green] {match['id'][:12]} — {result.get('message', 'success')}")


@app.command("reject")
def reject(
    task_id: str = typer.Argument(..., help="Task ID (prefix match)"),
    reason: str = typer.Option("", "-r", "--reason", help="Rejection reason"),
):
    """Reject a task and send feedback to the agent."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    if not reason:
        reason = typer.prompt("Rejection reason")

    client.reject_task(match["id"], reason)
    console.print(f"[yellow]Rejected[/yellow] {match['id'][:12]} — feedback sent to agent")


@app.command("review")
def review(
    project_path: str = typer.Option(".", "-p", "--project"),
):
    """List tasks in review status, ready for human review."""
    client = ZephClient()
    tasks = client.list_tasks(status="in_review")

    if not tasks:
        console.print("[dim]No tasks in review.[/dim]")
        return

    from .tasks import STATUS_COLORS, STATUS_ICONS

    table = Table(show_header=True, header_style="bold", title="Tasks Awaiting Review")
    table.add_column("ID", width=12)
    table.add_column("Title", min_width=20)
    table.add_column("Branch", min_width=20)
    table.add_column("Agent", width=14)

    for t in tasks:
        agent = t.get("assigned_to", "") or "unassigned"
        if len(agent) > 14:
            agent = agent[:14]

        table.add_row(
            t["id"][:12],
            t["title"],
            f"[cyan]{t.get('branch', 'n/a')}[/cyan]",
            agent,
        )

    console.print(table)
    console.print("\n[dim]Use 'zeph review diff <id>' to view changes, 'zeph review merge <id>' to merge.[/dim]\n")
