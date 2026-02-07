"""HTTP client for communicating with the zephd daemon."""

from __future__ import annotations

import os
import sys

import httpx

DAEMON_URL = os.environ.get("ZEPH_DAEMON_URL", "http://127.0.0.1:9800")
TIMEOUT = 10.0


def _url(path: str) -> str:
    return f"{DAEMON_URL}{path}"


def _handle(resp: httpx.Response) -> dict | list:
    if resp.status_code >= 400:
        try:
            detail = resp.json().get("detail", resp.text)
        except Exception:
            detail = resp.text
        print(f"Error ({resp.status_code}): {detail}", file=sys.stderr)
        raise SystemExit(1)
    return resp.json()


class ZephClient:
    def __init__(self) -> None:
        self._client = httpx.Client(base_url=DAEMON_URL, timeout=TIMEOUT)

    def _req(self, method: str, path: str, **kwargs) -> dict | list:
        try:
            resp = self._client.request(method, path, **kwargs)
        except httpx.ConnectError:
            print("Error: Cannot connect to zephd. Is the daemon running?", file=sys.stderr)
            print("Start it with: zeph up", file=sys.stderr)
            raise SystemExit(1)
        return _handle(resp)

    # --- Tasks ---

    def push_task(self, title: str, description: str = "", priority: int = 5,
                  depends_on: list[str] | None = None, tags: list[str] | None = None,
                  created_by: str = "user") -> dict:
        body = {"title": title, "description": description, "priority": priority,
                "created_by": created_by}
        if depends_on:
            body["depends_on"] = depends_on
        if tags:
            body["tags"] = tags
        return self._req("POST", "/tasks", json=body)

    def list_tasks(self, status: str | None = None, tag: str | None = None,
                   assigned_to: str | None = None) -> list:
        params = {}
        if status:
            params["status"] = status
        if tag:
            params["tag"] = tag
        if assigned_to:
            params["assigned_to"] = assigned_to
        return self._req("GET", "/tasks", params=params)

    def get_task(self, task_id: str) -> dict:
        return self._req("GET", f"/tasks/{task_id}")

    def update_task(self, task_id: str, **kwargs) -> dict:
        body = {k: v for k, v in kwargs.items() if v is not None}
        return self._req("PATCH", f"/tasks/{task_id}", json=body)

    def pop_task(self, agent_id: str) -> dict:
        return self._req("POST", "/tasks/pop", params={"agent_id": agent_id})

    def complete_task(self, task_id: str, output: str = "") -> dict:
        return self._req("POST", f"/tasks/{task_id}/complete", params={"output": output})

    def fail_task(self, task_id: str, reason: str = "") -> dict:
        return self._req("POST", f"/tasks/{task_id}/fail", params={"reason": reason})

    def delete_task(self, task_id: str) -> dict:
        return self._req("DELETE", f"/tasks/{task_id}")

    # --- Agents ---

    def register_agent(self, name: str, mode: str = "claude", project_path: str = ".") -> dict:
        return self._req("POST", "/agents", json={"name": name, "mode": mode, "project_path": project_path})

    def list_agents(self) -> list:
        return self._req("GET", "/agents")

    def get_agent(self, agent_id: str) -> dict:
        return self._req("GET", f"/agents/{agent_id}")

    def update_agent(self, agent_id: str, **kwargs) -> dict:
        body = {k: v for k, v in kwargs.items() if v is not None}
        return self._req("PATCH", f"/agents/{agent_id}", json=body)

    def heartbeat(self, agent_id: str) -> dict:
        return self._req("POST", f"/agents/{agent_id}/heartbeat")

    def deregister_agent(self, agent_id: str) -> dict:
        return self._req("DELETE", f"/agents/{agent_id}")

    # --- Layout / Session ---

    def get_layouts(self) -> dict:
        return self._req("GET", "/layouts")

    def apply_layout(self, name: str, project_path: str = ".") -> dict:
        return self._req("POST", f"/layouts/{name}/apply", params={"project_path": project_path})

    def session_up(self, project_path: str = ".", layout: str = "solo") -> dict:
        return self._req("POST", "/up", params={"project_path": project_path, "layout": layout})

    def session_down(self) -> dict:
        return self._req("POST", "/down")

    def status(self) -> dict:
        return self._req("GET", "/status")
