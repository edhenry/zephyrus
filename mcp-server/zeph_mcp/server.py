"""Zephyrus MCP server — exposes task stack tools to AI agents via JSON-RPC over stdio."""

from __future__ import annotations

import json
import os
import sys
from typing import Any

import httpx

DAEMON_URL = os.environ.get("ZEPH_DAEMON_URL", "http://127.0.0.1:9800")
AGENT_ID = os.environ.get("ZEPH_AGENT_ID", "unknown")
SESSION_ID = os.environ.get("ZEPH_SESSION_ID", "")

MCP_VERSION = "2024-11-05"

TOOLS = [
    {
        "name": "zeph_task_push",
        "description": "Add a new task to the shared task stack. Use this to create work items for yourself or other agents.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Short task title"},
                "description": {"type": "string", "description": "Detailed task description"},
                "priority": {"type": "integer", "minimum": 0, "maximum": 9, "description": "Priority (0=highest)"},
                "depends_on": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Task IDs that must complete before this task",
                },
                "tags": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Labels for categorization",
                },
            },
            "required": ["title"],
        },
    },
    {
        "name": "zeph_task_pop",
        "description": "Claim the next available task from the stack. Returns the highest-priority unclaimed task whose dependencies are satisfied.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "zeph_task_update",
        "description": "Update the status of your current task.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string", "description": "Task ID to update"},
                "status": {
                    "type": "string",
                    "enum": ["in_progress", "in_review", "done", "failed", "blocked"],
                    "description": "New task status",
                },
                "output": {"type": "string", "description": "Summary of work done or failure reason"},
            },
            "required": ["task_id", "status"],
        },
    },
    {
        "name": "zeph_status",
        "description": "Report your agent status to the command center.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "state": {
                    "type": "string",
                    "enum": ["idle", "working", "waiting", "done", "error"],
                    "description": "Current agent state",
                },
                "message": {"type": "string", "description": "Human-readable status message"},
            },
            "required": ["state"],
        },
    },
    {
        "name": "zeph_task_list",
        "description": "List all tasks on the stack. Useful for understanding what work is available or in progress.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "status": {
                    "type": "string",
                    "enum": ["pending", "claimed", "in_progress", "in_review", "done", "failed", "blocked"],
                    "description": "Filter by status",
                },
            },
        },
    },
    {
        "name": "zeph_agent_list",
        "description": "List all active agents in the command center.",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


class ZephMcpServer:
    def __init__(self) -> None:
        self.client = httpx.Client(base_url=DAEMON_URL, timeout=10.0)

    def handle_request(self, msg: dict[str, Any]) -> dict[str, Any] | None:
        method = msg.get("method", "")
        msg_id = msg.get("id")
        params = msg.get("params", {})

        if method == "initialize":
            return self._response(msg_id, {
                "protocolVersion": MCP_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "zephyrus-mcp-server", "version": "0.1.0"},
            })

        elif method == "notifications/initialized":
            self._report_status("idle", "Agent ready")
            return None  # Notifications don't get responses

        elif method == "tools/list":
            return self._response(msg_id, {"tools": TOOLS})

        elif method == "tools/call":
            tool_name = params.get("name", "")
            tool_args = params.get("arguments", {})
            return self._handle_tool_call(msg_id, tool_name, tool_args)

        elif method == "ping":
            return self._response(msg_id, {})

        else:
            return self._error(msg_id, -32601, f"Method not found: {method}")

    def _handle_tool_call(self, msg_id: Any, name: str, args: dict) -> dict:
        try:
            if name == "zeph_task_push":
                body = {"title": args["title"], "created_by": AGENT_ID}
                for key in ("description", "priority", "depends_on", "tags"):
                    if key in args:
                        body[key] = args[key]
                resp = self.client.post("/tasks", json=body)
                resp.raise_for_status()
                task = resp.json()
                return self._tool_result(msg_id, f"Created task {task['id'][:12]}: {task['title']}")

            elif name == "zeph_task_pop":
                resp = self.client.post("/tasks/pop", params={"agent_id": AGENT_ID})
                if resp.status_code == 404:
                    return self._tool_result(msg_id, "No tasks available.")
                resp.raise_for_status()
                task = resp.json()
                return self._tool_result(
                    msg_id,
                    f"Claimed task {task['id'][:12]}: {task['title']}\n"
                    f"Branch: {task.get('branch', 'n/a')}\n"
                    f"Description: {task.get('description', 'none')}",
                )

            elif name == "zeph_task_update":
                task_id = args["task_id"]
                status = args["status"]
                output = args.get("output", "")

                if status == "done":
                    resp = self.client.post(f"/tasks/{task_id}/complete", params={"output": output})
                elif status == "failed":
                    resp = self.client.post(f"/tasks/{task_id}/fail", params={"reason": output})
                else:
                    body = {"status": status}
                    if output:
                        body["output"] = output
                    resp = self.client.patch(f"/tasks/{task_id}", json=body)

                resp.raise_for_status()
                return self._tool_result(msg_id, f"Task {task_id[:12]} updated to {status}")

            elif name == "zeph_status":
                state = args["state"]
                message = args.get("message", "")
                self._report_status(state, message)
                return self._tool_result(msg_id, f"Status reported: {state}")

            elif name == "zeph_task_list":
                params = {}
                if "status" in args:
                    params["status"] = args["status"]
                resp = self.client.get("/tasks", params=params)
                resp.raise_for_status()
                tasks = resp.json()
                if not tasks:
                    return self._tool_result(msg_id, "No tasks found.")
                lines = []
                for t in tasks:
                    lines.append(f"[{t['status']}] {t['id'][:12]}: {t['title']} (P{t['priority']})")
                return self._tool_result(msg_id, "\n".join(lines))

            elif name == "zeph_agent_list":
                resp = self.client.get("/agents")
                resp.raise_for_status()
                agents_list = resp.json()
                if not agents_list:
                    return self._tool_result(msg_id, "No agents active.")
                lines = []
                for a in agents_list:
                    task_info = f" working on {a['current_task'][:12]}" if a.get('current_task') else ""
                    lines.append(f"[{a['status']}] {a['name']} ({a['mode']}){task_info}")
                return self._tool_result(msg_id, "\n".join(lines))

            else:
                return self._error(msg_id, -32602, f"Unknown tool: {name}")

        except httpx.ConnectError:
            return self._tool_result(
                msg_id,
                "Error: Cannot connect to zephd daemon. The command center may not be running.",
                is_error=True,
            )
        except Exception as e:
            return self._tool_result(msg_id, f"Error: {e}", is_error=True)

    def _report_status(self, state: str, message: str = "") -> None:
        try:
            self.client.patch(
                f"/agents/{AGENT_ID}",
                json={"status": state},
            )
        except Exception:
            pass  # Non-fatal

    def _response(self, msg_id: Any, result: dict) -> dict:
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    def _error(self, msg_id: Any, code: int, message: str) -> dict:
        return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}

    def _tool_result(self, msg_id: Any, text: str, is_error: bool = False) -> dict:
        return self._response(msg_id, {
            "content": [{"type": "text", "text": text}],
            "isError": is_error,
        })


def main() -> None:
    """Run the MCP server over stdio."""
    server = ZephMcpServer()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        response = server.handle_request(msg)
        if response is not None:
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
