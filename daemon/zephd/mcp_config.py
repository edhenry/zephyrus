"""MCP config writer — injects .mcp.json into agent working directories."""

from __future__ import annotations

import json
import logging
import shutil
from pathlib import Path

logger = logging.getLogger("zephd.mcp")

ZEPH_ROOT = Path(__file__).resolve().parent.parent.parent
MCP_BIN = ZEPH_ROOT / "bin" / "zeph-mcp"


def find_mcp_binary() -> str:
    """Find the zeph-mcp binary."""
    if MCP_BIN.exists():
        return str(MCP_BIN)
    which = shutil.which("zeph-mcp")
    if which:
        return which
    return str(MCP_BIN)


def write_mcp_config(
    target_dir: str,
    agent_id: str,
    daemon_url: str = "http://127.0.0.1:9800",
    extra_servers: dict | None = None,
) -> Path:
    """Write a .mcp.json file into the agent's working directory."""
    target = Path(target_dir)
    mcp_file = target / ".mcp.json"

    existing = {}
    if mcp_file.exists():
        try:
            existing = json.loads(mcp_file.read_text())
        except (json.JSONDecodeError, OSError):
            pass

    servers = existing.get("mcpServers", {})

    # Inject the zephyrus MCP server
    servers["zephyrus"] = {
        "command": find_mcp_binary(),
        "env": {
            "ZEPH_DAEMON_URL": daemon_url,
            "ZEPH_AGENT_ID": agent_id,
        },
    }

    # Merge extra servers (from project config or user config)
    if extra_servers:
        for name, config in extra_servers.items():
            if name != "zephyrus":  # Don't overwrite our own
                servers[name] = config

    existing["mcpServers"] = servers
    mcp_file.write_text(json.dumps(existing, indent=2) + "\n")
    logger.info("Wrote MCP config to %s (agent=%s)", mcp_file, agent_id)
    return mcp_file


def cleanup_mcp_config(target_dir: str) -> None:
    """Remove the zephyrus entry from .mcp.json, delete file if empty."""
    mcp_file = Path(target_dir) / ".mcp.json"
    if not mcp_file.exists():
        return

    try:
        data = json.loads(mcp_file.read_text())
        servers = data.get("mcpServers", {})
        servers.pop("zephyrus", None)

        if servers:
            data["mcpServers"] = servers
            mcp_file.write_text(json.dumps(data, indent=2) + "\n")
        else:
            mcp_file.unlink()
    except (json.JSONDecodeError, OSError):
        pass


def discover_project_mcp_servers(project_path: str) -> dict:
    """Discover MCP servers from a project's .mcp.json."""
    mcp_file = Path(project_path) / ".mcp.json"
    if not mcp_file.exists():
        return {}
    try:
        data = json.loads(mcp_file.read_text())
        return data.get("mcpServers", {})
    except (json.JSONDecodeError, OSError):
        return {}


def discover_user_mcp_servers() -> dict:
    """Discover MCP servers from user config at ~/.zephyrus/mcp/servers.json."""
    config_file = Path.home() / ".zephyrus" / "mcp" / "servers.json"
    if not config_file.exists():
        return {}
    try:
        data = json.loads(config_file.read_text())
        return data.get("mcpServers", {})
    except (json.JSONDecodeError, OSError):
        return {}


def save_user_mcp_server(name: str, config: dict) -> None:
    """Save a custom MCP server to user config."""
    config_file = Path.home() / ".zephyrus" / "mcp" / "servers.json"
    config_file.parent.mkdir(parents=True, exist_ok=True)

    existing = {}
    if config_file.exists():
        try:
            existing = json.loads(config_file.read_text())
        except (json.JSONDecodeError, OSError):
            pass

    servers = existing.get("mcpServers", {})
    servers[name] = config
    existing["mcpServers"] = servers
    config_file.write_text(json.dumps(existing, indent=2) + "\n")


def remove_user_mcp_server(name: str) -> bool:
    """Remove a custom MCP server from user config."""
    config_file = Path.home() / ".zephyrus" / "mcp" / "servers.json"
    if not config_file.exists():
        return False

    try:
        data = json.loads(config_file.read_text())
        servers = data.get("mcpServers", {})
        if name not in servers:
            return False
        del servers[name]
        data["mcpServers"] = servers
        config_file.write_text(json.dumps(data, indent=2) + "\n")
        return True
    except (json.JSONDecodeError, OSError):
        return False
