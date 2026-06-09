"""Data models for the Zephyrus Command Center."""

from __future__ import annotations

import enum
from datetime import datetime, timezone

from pydantic import BaseModel, Field


def _now() -> datetime:
    return datetime.now(timezone.utc)


# --- Task models ---


class TaskStatus(str, enum.Enum):
    PENDING = "pending"
    CLAIMED = "claimed"
    IN_PROGRESS = "in_progress"
    IN_REVIEW = "in_review"
    DONE = "done"
    FAILED = "failed"
    BLOCKED = "blocked"


class TaskCreate(BaseModel):
    title: str
    description: str = ""
    priority: int = Field(default=5, ge=0, le=9)
    created_by: str = "user"
    depends_on: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)


class TaskUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    status: TaskStatus | None = None
    priority: int | None = Field(default=None, ge=0, le=9)
    assigned_to: str | None = None
    output: str | None = None
    tags: list[str] | None = None


class Task(BaseModel):
    id: str
    title: str
    description: str = ""
    status: TaskStatus = TaskStatus.PENDING
    priority: int = 5
    created_by: str = "user"
    assigned_to: str | None = None
    depends_on: list[str] = Field(default_factory=list)
    branch: str | None = None
    worktree: str | None = None
    tags: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=_now)
    updated_at: datetime = Field(default_factory=_now)
    output: str | None = None


# --- Agent models ---


class AgentMode(str, enum.Enum):
    CLAUDE = "claude"
    GEMINI = "gemini"
    CODEX = "codex"
    AIDER = "aider"
    SHELL = "shell"


class AgentStatus(str, enum.Enum):
    STARTING = "starting"
    IDLE = "idle"
    WORKING = "working"
    WAITING = "waiting"
    DONE = "done"
    ERROR = "error"


class AgentCreate(BaseModel):
    name: str
    mode: AgentMode = AgentMode.CLAUDE
    project_path: str = "."


class Agent(BaseModel):
    id: str
    name: str
    mode: AgentMode = AgentMode.CLAUDE
    status: AgentStatus = AgentStatus.STARTING
    tmux_pane: str | None = None
    worktree: str | None = None
    current_task: str | None = None
    pid: int | None = None
    project_path: str = "."
    started_at: datetime = Field(default_factory=_now)
    last_seen: datetime = Field(default_factory=_now)


class AgentUpdate(BaseModel):
    status: AgentStatus | None = None
    current_task: str | None = None
    worktree: str | None = None
    tmux_pane: str | None = None
    pid: int | None = None


# --- Event models ---


class Event(BaseModel):
    type: str
    data: dict
    timestamp: datetime = Field(default_factory=_now)
