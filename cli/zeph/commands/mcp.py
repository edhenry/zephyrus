"""MCP server management commands."""

from __future__ import annotations

from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

from ..client import ZephClient

app = typer.Typer(help="Manage MCP servers")
console = Console()


@app.command("ls")
def ls(
    project_path: str = typer.Option(".", "-p", "--project", help="Project path"),
):
    """List all discovered MCP servers."""
    client = ZephClient()
    data = client.list_mcp_servers(project_path)

    project = data.get("project", {})
    user = data.get("user", {})

    if not project and not user:
        console.print("[dim]No MCP servers configured.[/dim]")
        return

    table = Table(show_header=True, header_style="bold", title="MCP Servers")
    table.add_column("Name", min_width=15)
    table.add_column("Command", min_width=20)
    table.add_column("Args", min_width=15)
    table.add_column("Source", width=10)

    for name, config in user.items():
        table.add_row(
            f"[cyan]{name}[/cyan]",
            config.get("command", ""),
            " ".join(config.get("args", [])),
            "[dim]user[/dim]",
        )

    for name, config in project.items():
        table.add_row(
            f"[green]{name}[/green]",
            config.get("command", ""),
            " ".join(config.get("args", [])),
            "[dim]project[/dim]",
        )

    console.print(table)


@app.command("add")
def add(
    name: str = typer.Argument(..., help="Server name"),
    command: str = typer.Argument(..., help="Command to run"),
    args: Optional[list[str]] = typer.Option(None, "-a", "--arg", help="Command arguments"),
    env_pairs: Optional[list[str]] = typer.Option(None, "-e", "--env", help="Environment vars (KEY=VALUE)"),
):
    """Add a user-level MCP server."""
    env = {}
    if env_pairs:
        for pair in env_pairs:
            if "=" in pair:
                k, v = pair.split("=", 1)
                env[k] = v
            else:
                console.print(f"[red]Invalid env format: {pair} (expected KEY=VALUE)[/red]")
                raise typer.Exit(1)

    client = ZephClient()
    client.add_mcp_server(name, command, args or [], env or {})
    console.print(f"[green]Added MCP server[/green] {name} ({command})")


@app.command("rm")
def rm(
    name: str = typer.Argument(..., help="Server name to remove"),
):
    """Remove a user-level MCP server."""
    client = ZephClient()
    client.remove_mcp_server(name)
    console.print(f"[red]Removed MCP server[/red] {name}")
