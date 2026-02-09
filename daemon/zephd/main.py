"""Zephyrus Command Center daemon — FastAPI application."""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

import ulid
import uvicorn
from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

from .agent_registry import AgentRegistry
from .db import Database
from .event_bus import EventBus
from .layout_engine import (
    apply_layout,
    available_layouts,
    create_session,
    kill_session,
    launch_agent_in_pane,
    load_layout,
    send_keys_to_pane,
)
from .mcp_config import (
    cleanup_mcp_config,
    discover_project_mcp_servers,
    discover_user_mcp_servers,
    save_user_mcp_server,
    remove_user_mcp_server,
    write_mcp_config,
)
from .models import (
    Agent,
    AgentCreate,
    AgentMode,
    AgentStatus,
    AgentUpdate,
    Task,
    TaskCreate,
    TaskStatus,
    TaskUpdate,
)
from .templates import render_prompt
from .worktree_manager import (
    clean_stale_worktrees,
    create_worktree,
    get_diff_summary,
    list_worktrees,
    merge_branch,
    delete_branch,
    remove_worktree,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("zephd")

# --- Globals ---
db = Database()
event_bus = EventBus()
agents = AgentRegistry(event_bus)

DAEMON_PORT = int(os.environ.get("ZEPH_PORT", "9800"))
PID_FILE = Path.home() / ".zephyrus" / "state" / "zephd.pid"


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.connect()
    await agents.start_heartbeat_monitor()
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))
    logger.info("zephd started on port %d (pid %d)", DAEMON_PORT, os.getpid())
    yield
    await agents.stop_heartbeat_monitor()
    await db.close()
    if PID_FILE.exists():
        PID_FILE.unlink()
    logger.info("zephd stopped")


app = FastAPI(title="Zephyrus Command Center", version="0.2.0", lifespan=lifespan)


# ============================================================
# Task endpoints
# ============================================================


@app.post("/tasks", response_model=Task, status_code=201)
async def create_task(body: TaskCreate):
    task_id = str(ulid.new())
    task = Task(id=task_id, **body.model_dump())
    task.branch = f"zeph/{task_id[:12]}-{_slugify(task.title)}"
    await db.insert_task(task)
    await event_bus.publish("task.created", task.model_dump(mode="json"))
    return task


@app.get("/tasks", response_model=list[Task])
async def list_tasks_endpoint(
    status: TaskStatus | None = None,
    assigned_to: str | None = None,
    tag: str | None = None,
):
    return await db.list_tasks(status=status, assigned_to=assigned_to, tag=tag)


@app.get("/tasks/{task_id}", response_model=Task)
async def get_task(task_id: str):
    task = await db.get_task(task_id)
    if not task:
        raise HTTPException(404, "Task not found")
    return task


@app.patch("/tasks/{task_id}", response_model=Task)
async def update_task(task_id: str, body: TaskUpdate):
    task = await db.update_task(task_id, body)
    if not task:
        raise HTTPException(404, "Task not found")
    await event_bus.publish("task.updated", task.model_dump(mode="json"))
    return task


@app.post("/tasks/pop", response_model=Task | None)
async def pop_task(agent_id: str = Query(...)):
    task = await db.pop_task(agent_id)
    if not task:
        raise HTTPException(404, "No tasks available")
    await event_bus.publish("task.claimed", {"task_id": task.id, "agent_id": agent_id})
    return task


@app.post("/tasks/{task_id}/complete", response_model=Task)
async def complete_task(task_id: str, output: str = ""):
    task = await db.get_task(task_id)
    if not task:
        raise HTTPException(404, "Task not found")
    update = TaskUpdate(status=TaskStatus.DONE, output=output or None)
    task = await db.update_task(task_id, update)
    await event_bus.publish(
        "task.completed",
        {"task_id": task_id, "agent_id": task.assigned_to, "output": output},
    )
    return task


@app.post("/tasks/{task_id}/fail", response_model=Task)
async def fail_task(task_id: str, reason: str = ""):
    task = await db.get_task(task_id)
    if not task:
        raise HTTPException(404, "Task not found")
    update = TaskUpdate(status=TaskStatus.FAILED, output=reason or None)
    task = await db.update_task(task_id, update)
    await event_bus.publish(
        "task.failed",
        {"task_id": task_id, "agent_id": task.assigned_to, "reason": reason},
    )
    return task


@app.delete("/tasks/{task_id}")
async def delete_task(task_id: str):
    deleted = await db.delete_task(task_id)
    if not deleted:
        raise HTTPException(404, "Task not found")
    return {"deleted": True}


# ============================================================
# Agent endpoints
# ============================================================


@app.post("/agents", response_model=Agent, status_code=201)
async def register_agent(body: AgentCreate):
    agent = agents.register(body)
    await event_bus.publish("agent.started", agent.model_dump(mode="json"))
    return agent


@app.get("/agents", response_model=list[Agent])
async def list_agents_endpoint():
    return agents.list_agents()


@app.get("/agents/{agent_id}", response_model=Agent)
async def get_agent(agent_id: str):
    agent = agents.get(agent_id)
    if not agent:
        raise HTTPException(404, "Agent not found")
    return agent


@app.patch("/agents/{agent_id}", response_model=Agent)
async def update_agent(agent_id: str, body: AgentUpdate):
    agent = agents.update(agent_id, body)
    if not agent:
        raise HTTPException(404, "Agent not found")
    await event_bus.publish(
        "agent.status",
        {"agent_id": agent_id, "status": agent.status.value},
    )
    return agent


@app.post("/agents/{agent_id}/heartbeat", response_model=Agent)
async def heartbeat_agent(agent_id: str):
    agent = agents.heartbeat(agent_id)
    if not agent:
        raise HTTPException(404, "Agent not found")
    return agent


@app.delete("/agents/{agent_id}")
async def deregister_agent(agent_id: str):
    agent = agents.get(agent_id)
    if agent and agent.worktree:
        cleanup_mcp_config(agent.worktree)
    ok = agents.deregister(agent_id)
    if not ok:
        raise HTTPException(404, "Agent not found")
    await event_bus.publish("agent.stopped", {"agent_id": agent_id})
    return {"deleted": True}


# ============================================================
# Layout endpoints
# ============================================================


@app.get("/layouts")
async def get_layouts():
    return {"layouts": available_layouts()}


@app.post("/layouts/{name}/apply")
async def apply_named_layout(name: str, project_path: str = Query(default=".")):
    try:
        layout = load_layout(name)
    except FileNotFoundError:
        raise HTTPException(404, f"Layout '{name}' not found")

    project_path = str(Path(project_path).resolve())
    pane_targets = await apply_layout(layout, project_path)
    launched = await _launch_agents_for_layout(layout, pane_targets, project_path)
    return {"layout": name, "panes": pane_targets, "agents": launched}


# ============================================================
# Worktree endpoints
# ============================================================


@app.get("/worktrees")
async def list_worktrees_endpoint(project_path: str = Query(default=".")):
    project_path = str(Path(project_path).resolve())
    return {"worktrees": await list_worktrees(project_path)}


@app.post("/worktrees")
async def create_worktree_endpoint(
    project_path: str = Query(...),
    branch: str = Query(...),
    task_id: str = Query(...),
    task_title: str = Query(default=""),
):
    wt = await create_worktree(project_path, branch, task_id, task_title)
    if not wt:
        raise HTTPException(500, "Failed to create worktree")
    return {"path": str(wt), "branch": branch, "task_id": task_id}


@app.delete("/worktrees")
async def remove_worktree_endpoint(
    project_path: str = Query(...),
    worktree_path: str = Query(...),
):
    ok = await remove_worktree(project_path, worktree_path)
    if not ok:
        raise HTTPException(500, "Failed to remove worktree")
    return {"removed": True}


@app.post("/worktrees/clean")
async def clean_worktrees_endpoint(project_path: str = Query(default=".")):
    project_path = str(Path(project_path).resolve())
    cleaned = await clean_stale_worktrees(project_path)
    return {"cleaned": cleaned, "count": len(cleaned)}


# ============================================================
# Review / Merge endpoints
# ============================================================


@app.get("/tasks/{task_id}/diff")
async def task_diff(task_id: str, project_path: str = Query(default=".")):
    task = await db.get_task(task_id)
    if not task:
        raise HTTPException(404, "Task not found")
    if not task.branch:
        raise HTTPException(400, "Task has no branch")
    project_path = str(Path(project_path).resolve())
    return await get_diff_summary(project_path, task.branch)


@app.post("/tasks/{task_id}/merge")
async def merge_task(task_id: str, project_path: str = Query(default="."), target: str = Query(default="main")):
    task = await db.get_task(task_id)
    if not task:
        raise HTTPException(404, "Task not found")
    if not task.branch:
        raise HTTPException(400, "Task has no branch")

    project_path = str(Path(project_path).resolve())
    ok, msg = await merge_branch(project_path, task.branch, target)
    if not ok:
        raise HTTPException(409, msg)

    await db.update_task(task_id, TaskUpdate(status=TaskStatus.DONE))

    if task.worktree:
        await remove_worktree(project_path, task.worktree)

    await delete_branch(project_path, task.branch)
    await event_bus.publish("task.completed", {"task_id": task_id, "merged": True})
    return {"merged": True, "message": msg}


class RejectBody(BaseModel):
    reason: str = ""


@app.post("/tasks/{task_id}/reject")
async def reject_task(task_id: str, body: RejectBody):
    task = await db.get_task(task_id)
    if not task:
        raise HTTPException(404, "Task not found")

    update = TaskUpdate(status=TaskStatus.IN_PROGRESS, output=f"REJECTED: {body.reason}")
    task = await db.update_task(task_id, update)

    if task.assigned_to:
        agent = agents.get(task.assigned_to)
        if agent and agent.tmux_pane:
            await send_keys_to_pane(
                agent.tmux_pane,
                f"Task rejected: {body.reason}. Please address the feedback and update the task.",
            )

    await event_bus.publish(
        "task.rejected",
        {"task_id": task_id, "agent_id": task.assigned_to, "reason": body.reason},
    )
    return {"rejected": True, "task_id": task_id}


# ============================================================
# MCP server management
# ============================================================


@app.get("/mcp/servers")
async def list_mcp_servers(project_path: str = Query(default=".")):
    project_path = str(Path(project_path).resolve())
    project_servers = discover_project_mcp_servers(project_path)
    user_servers = discover_user_mcp_servers()
    return {
        "project": project_servers,
        "user": user_servers,
        "combined": {**user_servers, **project_servers},
    }


class McpServerBody(BaseModel):
    name: str
    command: str
    args: list[str] = []
    env: dict[str, str] = {}


@app.post("/mcp/servers")
async def add_mcp_server(body: McpServerBody):
    config = {"command": body.command}
    if body.args:
        config["args"] = body.args
    if body.env:
        config["env"] = body.env
    save_user_mcp_server(body.name, config)
    return {"added": body.name}


@app.delete("/mcp/servers/{name}")
async def remove_mcp_server_endpoint(name: str):
    ok = remove_user_mcp_server(name)
    if not ok:
        raise HTTPException(404, f"MCP server '{name}' not found")
    return {"removed": name}


# ============================================================
# Session lifecycle
# ============================================================


@app.post("/up")
async def session_up(project_path: str = Query(default="."), layout: str = Query(default="solo")):
    """Start the full command center."""
    try:
        layout_spec = load_layout(layout)
    except FileNotFoundError:
        raise HTTPException(404, f"Layout '{layout}' not found")

    project_path = str(Path(project_path).resolve())
    pane_targets = await apply_layout(layout_spec, project_path)
    launched = await _launch_agents_for_layout(layout_spec, pane_targets, project_path)

    return {
        "status": "running",
        "layout": layout,
        "panes": pane_targets,
        "agents": launched,
    }


@app.post("/down")
async def session_down():
    """Shut down the command center."""
    for agent in agents.list_agents():
        if agent.worktree:
            cleanup_mcp_config(agent.worktree)
        agents.deregister(agent.id)

    await kill_session()
    return {"status": "stopped"}


# ============================================================
# Status
# ============================================================


@app.get("/status")
async def get_status():
    all_tasks = await db.list_tasks()
    agent_list = agents.list_agents()
    return {
        "daemon": "running",
        "port": DAEMON_PORT,
        "pid": os.getpid(),
        "agents": {
            "total": len(agent_list),
            "working": sum(1 for a in agent_list if a.status == AgentStatus.WORKING),
            "idle": sum(1 for a in agent_list if a.status in (AgentStatus.IDLE, AgentStatus.STARTING)),
            "error": sum(1 for a in agent_list if a.status == AgentStatus.ERROR),
        },
        "tasks": {
            "total": len(all_tasks),
            "pending": sum(1 for t in all_tasks if t.status == TaskStatus.PENDING),
            "in_progress": sum(1 for t in all_tasks if t.status in (TaskStatus.CLAIMED, TaskStatus.IN_PROGRESS)),
            "in_review": sum(1 for t in all_tasks if t.status == TaskStatus.IN_REVIEW),
            "done": sum(1 for t in all_tasks if t.status == TaskStatus.DONE),
            "failed": sum(1 for t in all_tasks if t.status == TaskStatus.FAILED),
        },
    }


# ============================================================
# WebSocket
# ============================================================


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    await event_bus.subscribe(ws)
    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        await event_bus.unsubscribe(ws)


# ============================================================
# Helpers
# ============================================================


async def _launch_agents_for_layout(layout_spec, pane_targets, project_path):
    """Register agents, inject MCP config, spawn CLI processes."""
    launched = []
    project_servers = discover_project_mcp_servers(project_path)
    user_servers = discover_user_mcp_servers()
    extra_servers = {**user_servers, **project_servers}

    for pane in layout_spec.panes:
        if pane.type != "agent" or pane.id not in pane_targets:
            continue

        agent = agents.register(
            AgentCreate(name=pane.id, mode=AgentMode(pane.mode), project_path=project_path)
        )

        work_dir = project_path
        write_mcp_config(work_dir, agent.id, f"http://localhost:{DAEMON_PORT}", extra_servers)

        pid = await launch_agent_in_pane(
            pane_targets[pane.id], pane.mode, work_dir, agent.id,
            env_vars={
                "ZEPH_AGENT_ID": agent.id,
                "ZEPH_DAEMON_URL": f"http://localhost:{DAEMON_PORT}",
            },
        )

        agent.tmux_pane = pane_targets[pane.id]
        agent.pid = pid
        agent.worktree = work_dir
        launched.append(agent.model_dump(mode="json"))

    return launched


def _slugify(text: str, max_len: int = 30) -> str:
    slug = text.lower().replace(" ", "-")
    slug = "".join(c for c in slug if c.isalnum() or c == "-")
    return slug[:max_len].rstrip("-")


def run() -> None:
    uvicorn.run("zephd.main:app", host="127.0.0.1", port=DAEMON_PORT, log_level="info")


if __name__ == "__main__":
    run()
