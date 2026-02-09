"""Agent prompt templates for initial task assignment."""

from __future__ import annotations

from pathlib import Path

TEMPLATES_DIR = Path.home() / ".zephyrus" / "templates"

DEFAULT_TEMPLATE = """\
You are agent {agent_name} in the Zephyrus Command Center.

Your current task: {task_title}
Task ID: {task_id}
Branch: {branch}
Priority: {priority}

{description}

## Instructions

1. Work on the task in your current directory (an isolated git worktree).
2. Use the `zeph_task_update` MCP tool to report progress:
   - Set status to "in_progress" when you start working.
   - Set status to "in_review" when you're done and ready for human review.
   - Set status to "failed" if you hit an unrecoverable blocker.
3. Use `zeph_task_push` to create subtasks if needed.
4. Use `zeph_task_pop` to get your next task when done.
5. Use `zeph_status` to report your agent state (working/idle/waiting).
6. Commit your changes to the branch: {branch}
"""

TEMPLATES = {
    "claude": DEFAULT_TEMPLATE,
    "gemini": DEFAULT_TEMPLATE,
    "codex": DEFAULT_TEMPLATE,
    "aider": DEFAULT_TEMPLATE,
    "shell": "# Task: {task_title}\n# Branch: {branch}\n# ID: {task_id}\n",
}


def load_template(mode: str) -> str:
    """Load a prompt template. Checks user overrides first, then defaults."""
    user_template = TEMPLATES_DIR / f"{mode}.txt"
    if user_template.exists():
        return user_template.read_text()
    return TEMPLATES.get(mode, DEFAULT_TEMPLATE)


def render_prompt(
    mode: str,
    agent_name: str,
    task_id: str,
    task_title: str,
    branch: str,
    description: str = "",
    priority: int = 5,
) -> str:
    """Render a prompt template with task details."""
    template = load_template(mode)
    return template.format(
        agent_name=agent_name,
        task_id=task_id,
        task_title=task_title,
        branch=branch,
        description=description or "(no description)",
        priority=priority,
    )


def save_template(mode: str, content: str) -> Path:
    """Save a custom template."""
    TEMPLATES_DIR.mkdir(parents=True, exist_ok=True)
    path = TEMPLATES_DIR / f"{mode}.txt"
    path.write_text(content)
    return path
