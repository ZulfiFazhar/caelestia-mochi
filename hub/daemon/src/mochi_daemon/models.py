from __future__ import annotations

import time
from enum import StrEnum
from typing import Any
from pydantic import BaseModel, Field


class MochiState(StrEnum):
    SLEEPING = "sleeping"
    IDLE = "idle"
    THINKING = "thinking"
    WORKING = "working"
    SEARCHING = "searching"
    APPROVAL = "approval"
    QUESTION = "question"
    DONE = "done"

    @classmethod
    def _missing_(cls, value: object) -> MochiState | None:
        if isinstance(value, str):
            val_lower = value.lower()
            if val_lower in ("finished", "complete", "completed", "success"):
                return cls.DONE
            for member in cls:
                if member.value == val_lower:
                    return member
        return None


class AgentInfo(BaseModel):
    name: str
    command: str = ""
    pid: int | None = None
    status: str = "idle"
    cpu: float = 0.0
    memory: float = 0.0
    details: dict[str, Any] = Field(default_factory=dict)

    # ponytail: explicit __init__ allows both positional and keyword instantiation without custom metaclass
    def __init__(
        self,
        name: str = "",
        command: str = "",
        pid: int | None = None,
        status: str = "idle",
        cpu: float = 0.0,
        memory: float = 0.0,
        details: dict[str, Any] | None = None,
        **kwargs: Any,
    ):
        super().__init__(
            name=name,
            command=command,
            pid=pid,
            status=status,
            cpu=cpu,
            memory=memory,
            details=details if details is not None else {},
            **kwargs,
        )


class SystemState(BaseModel):
    timestamp: float = Field(default_factory=time.time)
    agents: list[AgentInfo] = Field(default_factory=list)
    active_agent: AgentInfo | None = None
    mochi_state: MochiState = MochiState.IDLE

    def __init__(
        self,
        timestamp: float | None = None,
        agents: list[AgentInfo] | None = None,
        active_agent: AgentInfo | None = None,
        mochi_state: MochiState | str = MochiState.IDLE,
        **kwargs: Any,
    ):
        if isinstance(mochi_state, str) and not isinstance(mochi_state, MochiState):
            try:
                mochi_state = MochiState(mochi_state)
            except ValueError:
                mochi_state = MochiState.IDLE
        super().__init__(
            timestamp=time.time() if timestamp is None else timestamp,
            agents=agents if agents is not None else [],
            active_agent=active_agent,
            mochi_state=mochi_state,
            **kwargs,
        )
