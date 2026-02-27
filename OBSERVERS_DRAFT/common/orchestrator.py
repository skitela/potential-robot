from __future__ import annotations

from typing import Protocol


class AgentLike(Protocol):
    def run_cycle(self) -> dict:  # pragma: no cover - protocol
        ...


class ObserverOrchestrator:
    """Optional scheduler facade for observer agents (no runtime trading integration)."""

    def __init__(
        self,
        ops_agent: AgentLike,
        rd_agent: AgentLike,
        rec_agent: AgentLike,
        guardian_agent: AgentLike,
    ) -> None:
        self.ops_agent = ops_agent
        self.rd_agent = rd_agent
        self.rec_agent = rec_agent
        self.guardian_agent = guardian_agent

    def tick_short_interval(self) -> dict:
        return {"ops": self.ops_agent.run_cycle()}

    def tick_hourly(self) -> dict:
        return {"guardian": self.guardian_agent.run_cycle()}

    def tick_daily_post_session(self) -> dict:
        return {
            "rd": self.rd_agent.run_cycle(),
            "recommendations": self.rec_agent.run_cycle(),
        }

