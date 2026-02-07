"""In-memory agent registry with heartbeat tracking."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

import ulid

from .event_bus import EventBus
from .models import Agent, AgentCreate, AgentMode, AgentStatus, AgentUpdate

logger = logging.getLogger("zephd.agents")

HEARTBEAT_TIMEOUT_SECONDS = 90


class AgentRegistry:
    def __init__(self, event_bus: EventBus) -> None:
        self._agents: dict[str, Agent] = {}
        self._event_bus = event_bus
        self._heartbeat_task: asyncio.Task | None = None

    async def start_heartbeat_monitor(self) -> None:
        self._heartbeat_task = asyncio.create_task(self._monitor_heartbeats())

    async def stop_heartbeat_monitor(self) -> None:
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

    async def _monitor_heartbeats(self) -> None:
        while True:
            await asyncio.sleep(30)
            now = datetime.now(timezone.utc)
            for agent in list(self._agents.values()):
                if agent.status in (AgentStatus.DONE, AgentStatus.ERROR):
                    continue
                elapsed = (now - agent.last_seen).total_seconds()
                if elapsed > HEARTBEAT_TIMEOUT_SECONDS:
                    logger.warning(
                        "Agent %s (%s) heartbeat timeout (%.0fs)",
                        agent.name,
                        agent.id,
                        elapsed,
                    )
                    agent.status = AgentStatus.ERROR
                    await self._event_bus.publish(
                        "agent.status",
                        {"agent_id": agent.id, "status": "error", "reason": "heartbeat_timeout"},
                    )

    def register(self, create: AgentCreate) -> Agent:
        agent_id = str(ulid.new())
        agent = Agent(
            id=agent_id,
            name=create.name,
            mode=create.mode,
            project_path=create.project_path,
        )
        self._agents[agent_id] = agent
        logger.info("Registered agent %s (%s, mode=%s)", agent.name, agent.id, agent.mode.value)
        return agent

    def get(self, agent_id: str) -> Agent | None:
        return self._agents.get(agent_id)

    def get_by_name(self, name: str) -> Agent | None:
        for agent in self._agents.values():
            if agent.name == name:
                return agent
        return None

    def list_agents(self) -> list[Agent]:
        return list(self._agents.values())

    def update(self, agent_id: str, update: AgentUpdate) -> Agent | None:
        agent = self._agents.get(agent_id)
        if not agent:
            return None

        changes = update.model_dump(exclude_none=True)
        for key, value in changes.items():
            setattr(agent, key, value)
        agent.last_seen = datetime.now(timezone.utc)
        return agent

    def heartbeat(self, agent_id: str) -> Agent | None:
        agent = self._agents.get(agent_id)
        if agent:
            agent.last_seen = datetime.now(timezone.utc)
        return agent

    def deregister(self, agent_id: str) -> bool:
        if agent_id in self._agents:
            agent = self._agents.pop(agent_id)
            logger.info("Deregistered agent %s (%s)", agent.name, agent.id)
            return True
        return False
