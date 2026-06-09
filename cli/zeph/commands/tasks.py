"""Task management commands."""

from __future__ import annotations

from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

from ..client import ZephClient

app = typer.Typer(help="Manage the task stack")
console = Console()

STATUS_COLORS = {
    "pending": "white",
    "claimed": "cyan",
    "in_progress": "yellow",
    "in_review": "magenta",
    "done": "green",
    "failed": "red",
    "blocked": "red",
}

STATUS_ICONS = {
    "pending": " ",
    "claimed": ">",
    "in_progress": "~",
    "in_review": "?",
    "done": "+",
    "failed": "x",
    "blocked": "!",
}


@app.command("push")
def push(
    title: str = typer.Argument(..., help="Task title"),
    description: str = typer.Option("", "-d", "--desc", help="Task description"),
    priority: int = typer.Option(5, "-p", "--priority", min=0, max=9, help="Priority (0=highest, 9=lowest)"),
    depends_on: Optional[list[str]] = typer.Option(None, "--depends-on", help="Task IDs this depends on"),
    tags: Optional[list[str]] = typer.Option(None, "-t", "--tag", help="Tags"),
):
    """Push a new task onto the stack."""
    client = ZephClient()
    task = client.push_task(title, description, priority, depends_on, tags)
    console.print(f"[green]Created task[/green] {task['id'][:12]} — {task['title']}")
    if task.get("branch"):
        console.print(f"  branch: [cyan]{task['branch']}[/cyan]")


@app.command("ls")
def ls(
    status: Optional[str] = typer.Option(None, "-s", "--status", help="Filter by status"),
    tag: Optional[str] = typer.Option(None, "-t", "--tag", help="Filter by tag"),
    assigned_to: Optional[str] = typer.Option(None, "-a", "--assigned", help="Filter by agent"),
    all_tasks: bool = typer.Option(False, "--all", help="Show completed and failed tasks too"),
):
    """List tasks on the stack."""
    client = ZephClient()
    tasks = client.list_tasks(status=status, tag=tag, assigned_to=assigned_to)

    if not all_tasks and not status:
        tasks = [t for t in tasks if t["status"] not in ("done", "failed")]

    if not tasks:
        console.print("[dim]No tasks.[/dim]")
        return

    table = Table(show_header=True, header_style="bold")
    table.add_column("", width=1)
    table.add_column("ID", width=12)
    table.add_column("P", width=2, justify="center")
    table.add_column("Title", min_width=20)
    table.add_column("Status", width=12)
    table.add_column("Agent", width=12)
    table.add_column("Tags", width=15)

    for t in tasks:
        st = t["status"]
        color = STATUS_COLORS.get(st, "white")
        icon = STATUS_ICONS.get(st, " ")
        agent = t.get("assigned_to", "") or ""
        if agent and len(agent) > 12:
            agent = agent[:12]
        tags_str = ", ".join(t.get("tags", []))

        table.add_row(
            f"[{color}]{icon}[/{color}]",
            t["id"][:12],
            str(t["priority"]),
            t["title"],
            f"[{color}]{st}[/{color}]",
            agent,
            tags_str,
        )

    console.print(table)


@app.command("show")
def show(task_id: str = typer.Argument(..., help="Task ID (prefix match)")):
    """Show task details."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    task = client.get_task(match["id"])
    st = task["status"]
    color = STATUS_COLORS.get(st, "white")

    console.print(f"\n[bold]{task['title']}[/bold]")
    console.print(f"  ID:       {task['id']}")
    console.print(f"  Status:   [{color}]{st}[/{color}]")
    console.print(f"  Priority: {task['priority']}")
    console.print(f"  Branch:   [cyan]{task.get('branch', 'n/a')}[/cyan]")
    console.print(f"  Agent:    {task.get('assigned_to', 'unassigned')}")
    console.print(f"  Tags:     {', '.join(task.get('tags', [])) or 'none'}")

    if task.get("depends_on"):
        console.print(f"  Depends:  {', '.join(task['depends_on'])}")
    if task.get("description"):
        console.print(f"\n  {task['description']}")
    if task.get("output"):
        console.print(f"\n  [dim]Output:[/dim] {task['output']}")
    console.print()


@app.command("done")
def done(
    task_id: str = typer.Argument(..., help="Task ID"),
    output: str = typer.Option("", "-o", "--output", help="Completion summary"),
):
    """Mark a task as done."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    task = client.complete_task(match["id"], output)
    console.print(f"[green]Completed[/green] {task['id'][:12]} — {task['title']}")


@app.command("fail")
def fail(
    task_id: str = typer.Argument(..., help="Task ID"),
    reason: str = typer.Option("", "-r", "--reason", help="Failure reason"),
):
    """Mark a task as failed."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    task = client.fail_task(match["id"], reason)
    console.print(f"[red]Failed[/red] {task['id'][:12]} — {task['title']}")


@app.command("edit")
def edit(
    task_id: str = typer.Argument(..., help="Task ID"),
    title: Optional[str] = typer.Option(None, "--title"),
    priority: Optional[int] = typer.Option(None, "-p", "--priority", min=0, max=9),
    status: Optional[str] = typer.Option(None, "-s", "--status"),
    assign: Optional[str] = typer.Option(None, "-a", "--assign", help="Assign to agent"),
):
    """Edit a task."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    kwargs = {}
    if title is not None:
        kwargs["title"] = title
    if priority is not None:
        kwargs["priority"] = priority
    if status is not None:
        kwargs["status"] = status
    if assign is not None:
        kwargs["assigned_to"] = assign

    if not kwargs:
        console.print("[dim]Nothing to update.[/dim]")
        return

    task = client.update_task(match["id"], **kwargs)
    console.print(f"[green]Updated[/green] {task['id'][:12]} — {task['title']}")


@app.command("rm")
def rm(task_id: str = typer.Argument(..., help="Task ID")):
    """Remove a task from the stack."""
    client = ZephClient()
    tasks = client.list_tasks()
    match = _find_task(tasks, task_id)
    if not match:
        console.print(f"[red]Task not found: {task_id}[/red]")
        raise typer.Exit(1)

    client.delete_task(match["id"])
    console.print(f"[red]Removed[/red] {match['id'][:12]} — {match['title']}")


def _find_task(tasks: list[dict], prefix: str) -> dict | None:
    """Find a task by ID prefix match."""
    for t in tasks:
        if t["id"].startswith(prefix) or t["id"][:12].startswith(prefix):
            return t
    return None
