"""Zephyrus Command Center daemon — FastAPI application."""

from __future__ import annotations

import asyncio
import logging
import os
import signal
import sys
from contextlib import asynccontextmanager
from pathlib import Path

import ulid
import uvicorn
from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect

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
    # Startup
    await db.connect()
    await agents.start_heartbeat_monitor()
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))
    logger.info("zephd started on port %d (pid %d)", DAEMON_PORT, os.getpid())
    yield
    # Shutdown
    await agents.stop_heartbeat_monitor()
    await db.close()
    if PID_FILE.exists():
        PID_FILE.unlink()
    logger.info("zephd stopped")


app = FastAPI(title="Zephyrus Command Center", version="0.1.0", lifespan=lifespan)


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
async def list_tasks(
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
async def list_agents():
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

    pane_targets = await apply_layout(layout, project_path)

    # Launch agents for agent-type panes
    launched = []
    for pane in layout.panes:
        if pane.type == "agent" and pane.id in pane_targets:
            agent = agents.register(
                AgentCreate(name=pane.id, mode=AgentMode(pane.mode), project_path=project_path)
            )
            pid = await launch_agent_in_pane(
                pane_targets[pane.id],
                pane.mode,
                project_path,
                agent.id,
                env_vars={
                    "ZEPH_AGENT_ID": agent.id,
                    "ZEPH_DAEMON_URL": f"http://localhost:{DAEMON_PORT}",
                },
            )
            agent.tmux_pane = pane_targets[pane.id]
            agent.pid = pid
            launched.append(agent.model_dump(mode="json"))

    return {"layout": name, "panes": pane_targets, "agents": launched}


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

    pane_targets = await apply_layout(layout_spec, project_path)

    launched = []
    for pane in layout_spec.panes:
        if pane.type == "agent" and pane.id in pane_targets:
            agent = agents.register(
                AgentCreate(name=pane.id, mode=AgentMode(pane.mode), project_path=project_path)
            )
            pid = await launch_agent_in_pane(
                pane_targets[pane.id],
                pane.mode,
                project_path,
                agent.id,
                env_vars={
                    "ZEPH_AGENT_ID": agent.id,
                    "ZEPH_DAEMON_URL": f"http://localhost:{DAEMON_PORT}",
                },
            )
            agent.tmux_pane = pane_targets[pane.id]
            agent.pid = pid
            launched.append(agent.model_dump(mode="json"))

    return {
        "status": "running",
        "layout": layout,
        "panes": pane_targets,
        "agents": launched,
    }


@app.post("/down")
async def session_down():
    """Shut down the command center."""
    # Deregister all agents
    for agent in agents.list_agents():
        agents.deregister(agent.id)

    await kill_session()
    return {"status": "stopped"}


# ============================================================
# Status
# ============================================================


@app.get("/status")
async def get_status():
    all_tasks = await db.list_tasks()
    return {
        "daemon": "running",
        "port": DAEMON_PORT,
        "pid": os.getpid(),
        "agents": len(agents.list_agents()),
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
            # Keep connection alive, wait for client messages (ping/pong)
            await ws.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        await event_bus.unsubscribe(ws)


# ============================================================
# Helpers
# ============================================================


def _slugify(text: str, max_len: int = 30) -> str:
    slug = text.lower().replace(" ", "-")
    slug = "".join(c for c in slug if c.isalnum() or c == "-")
    return slug[:max_len].rstrip("-")


def run() -> None:
    """Entry point for `zephd` command."""
    uvicorn.run(
        "zephd.main:app",
        host="127.0.0.1",
        port=DAEMON_PORT,
        log_level="info",
    )


if __name__ == "__main__":
    run()
