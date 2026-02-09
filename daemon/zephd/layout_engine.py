"""tmux layout engine — creates and manages pane arrangements."""

from __future__ import annotations

import asyncio
import logging
import shutil
from dataclasses import dataclass, field
from pathlib import Path

import yaml

logger = logging.getLogger("zephd.layout")

LAYOUT_DIR = Path(__file__).resolve().parent.parent.parent / "tmux" / "layouts"
SESSION_NAME = "zephyrus"


@dataclass
class PaneSpec:
    id: str
    type: str  # "agent", "nvim", "lazygit", "dashboard", "shell"
    mode: str = "claude"
    args: list[str] = field(default_factory=list)


@dataclass
class LayoutSpec:
    name: str
    description: str
    panes: list[PaneSpec]


def load_layout(name: str) -> LayoutSpec:
    """Load a layout definition from YAML."""
    layout_file = LAYOUT_DIR / f"{name}.yaml"
    if not layout_file.exists():
        raise FileNotFoundError(f"Layout not found: {layout_file}")

    with open(layout_file) as f:
        data = yaml.safe_load(f)

    panes = []
    for p in data.get("panes", []):
        panes.append(
            PaneSpec(
                id=p["id"],
                type=p["type"],
                mode=p.get("mode", "claude"),
                args=p.get("args", []),
            )
        )

    return LayoutSpec(
        name=data["name"],
        description=data.get("description", ""),
        panes=panes,
    )


def available_layouts() -> list[str]:
    """Return names of available layout files."""
    if not LAYOUT_DIR.exists():
        return []
    return sorted(p.stem for p in LAYOUT_DIR.glob("*.yaml"))


async def _run(cmd: str) -> tuple[int, str]:
    """Run a shell command and return (returncode, stdout)."""
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    output = stdout.decode().strip()
    if proc.returncode != 0:
        err = stderr.decode().strip()
        logger.debug("Command failed: %s -> %s", cmd, err)
    return proc.returncode, output


async def session_exists() -> bool:
    code, _ = await _run(f"tmux has-session -t {SESSION_NAME} 2>/dev/null")
    return code == 0


async def create_session(project_path: str) -> None:
    """Create the base tmux session if it doesn't exist."""
    if await session_exists():
        logger.info("Session %s already exists", SESSION_NAME)
        return

    await _run(f"tmux new-session -d -s {SESSION_NAME} -c {project_path}")
    logger.info("Created tmux session: %s", SESSION_NAME)


async def kill_session() -> None:
    """Kill the zephyrus tmux session."""
    if await session_exists():
        await _run(f"tmux kill-session -t {SESSION_NAME}")
        logger.info("Killed tmux session: %s", SESSION_NAME)


async def apply_layout(layout: LayoutSpec, project_path: str) -> dict[str, str]:
    """Apply a layout to the tmux session. Returns mapping of pane_id -> tmux pane target.

    If the session already exists with panes, returns the existing pane targets
    rather than creating duplicate splits.
    """
    already_existed = await session_exists()
    await create_session(project_path)

    pane_targets: dict[str, str] = {}
    agent_panes = [p for p in layout.panes if p.type == "agent"]
    other_panes = [p for p in layout.panes if p.type != "agent"]
    all_panes = agent_panes + other_panes

    if not all_panes:
        return pane_targets

    # If session already existed, map existing panes to layout pane IDs
    if already_existed:
        _, existing = await _run(
            f"tmux list-panes -t {SESSION_NAME} -F '#{{pane_index}}'"
        )
        existing_indices = [
            line.strip() for line in existing.strip().split("\n") if line.strip()
        ]
        for i, pane in enumerate(all_panes):
            if i < len(existing_indices):
                pane_targets[pane.id] = f"{SESSION_NAME}:0.{existing_indices[i]}"
        logger.info(
            "Session already exists with %d panes, reusing targets",
            len(existing_indices),
        )
        return pane_targets

    # Fresh session — the first pane is already created
    pane_targets[all_panes[0].id] = f"{SESSION_NAME}:0.0"

    # Additional panes are created by splitting
    for i, pane in enumerate(all_panes[1:], 1):
        if i <= len(agent_panes) and i % 2 == 1:
            split_flag = "-h"
        else:
            split_flag = "-v"

        _, output = await _run(
            f"tmux split-window {split_flag} -t {SESSION_NAME} -c {project_path} -P -F '#{{pane_index}}'"
        )
        idx = output.strip()
        if idx:
            pane_targets[pane.id] = f"{SESSION_NAME}:0.{idx}"
        else:
            pane_targets[pane.id] = f"{SESSION_NAME}:0.{i}"

    # Re-tile for even spacing
    await _run(f"tmux select-layout -t {SESSION_NAME} tiled")

    # Now launch the appropriate program in each pane
    for pane in all_panes:
        target = pane_targets.get(pane.id)
        if not target:
            continue

        if pane.type == "nvim":
            nvim = shutil.which("nvim") or "nvim"
            args_str = " ".join(pane.args) if pane.args else ""
            await _run(f"tmux send-keys -t {target} '{nvim} {args_str}' Enter")
        elif pane.type == "lazygit":
            lg = shutil.which("lazygit") or "lazygit"
            await _run(f"tmux send-keys -t {target} '{lg}' Enter")
        # Agent panes are launched separately via _launch_agents_for_layout

    logger.info("Applied layout %s with %d panes", layout.name, len(all_panes))
    return pane_targets


async def is_pane_busy(pane_target: str) -> bool:
    """Check if a tmux pane already has a running process (beyond the shell)."""
    _, output = await _run(
        f"tmux list-panes -t {pane_target} -F '#{{pane_current_command}}'"
    )
    cmd = output.strip().split("\n")[0] if output.strip() else ""
    # If the pane is running something other than a shell, it's busy
    shells = {"bash", "zsh", "fish", "sh", "dash", "tcsh", "csh", "login"}
    return cmd not in shells and cmd != ""


async def launch_agent_in_pane(
    pane_target: str,
    mode: str,
    project_path: str,
    agent_id: str,
    env_vars: dict[str, str] | None = None,
) -> int | None:
    """Launch an AI agent CLI in a specific tmux pane. Returns the PID or None.

    Skips launching if the pane already has a running process to prevent
    duplicate agent launches.
    """
    # Don't re-launch if pane already has something running
    if await is_pane_busy(pane_target):
        logger.info("Pane %s already busy, skipping agent launch", pane_target)
        _, pid_str = await _run(f"tmux list-panes -t {pane_target} -F '#{{pane_pid}}'")
        try:
            return int(pid_str.strip().split('\n')[0])
        except (ValueError, IndexError):
            return None

    cli_commands = {
        "claude": "claude",
        "gemini": "gemini",
        "codex": "codex",
        "aider": "aider",
        "shell": "${SHELL:-bash}",
    }

    cmd = cli_commands.get(mode, "${SHELL:-bash}")

    # Set environment variables in the pane
    if env_vars:
        for key, value in env_vars.items():
            await _run(f"tmux send-keys -t {pane_target} 'export {key}={value}' Enter")

    # Launch the agent
    await _run(f"tmux send-keys -t {pane_target} 'cd {project_path} && {cmd}' Enter")

    # Try to get the PID
    _, pid_str = await _run(f"tmux list-panes -t {pane_target} -F '#{{pane_pid}}'")
    try:
        return int(pid_str.strip().split('\n')[0])
    except (ValueError, IndexError):
        return None


async def send_keys_to_pane(pane_target: str, text: str) -> None:
    """Send text to a tmux pane (e.g., to deliver feedback to an agent)."""
    escaped = text.replace("'", "'\\''")
    await _run(f"tmux send-keys -t {pane_target} '{escaped}' Enter")


async def get_pane_count() -> int:
    """Get the number of panes in the zephyrus session."""
    if not await session_exists():
        return 0
    _, output = await _run(f"tmux list-panes -t {SESSION_NAME} 2>/dev/null | wc -l")
    try:
        return int(output.strip())
    except ValueError:
        return 0
