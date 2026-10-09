from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Callable

from fastapi import APIRouter, Request
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

from mochi_daemon.models import SystemState
from mochi_daemon.monitor import AgentMonitorService

logger = logging.getLogger(__name__)


class ApprovalPayload(BaseModel):
    approved: bool = True
    reason: str = ""


class EventBroadcaster:
    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue[dict[str, Any]]] = set()
        self.latest_state: SystemState | None = None

    def subscribe(self) -> asyncio.Queue[dict[str, Any]]:
        # ponytail: bounded queue drops stale messages if a slow client falls behind
        q: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=100)
        self._subscribers.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue[dict[str, Any]]) -> None:
        self._subscribers.discard(q)

    async def broadcast(self, event: str, data: Any) -> None:
        if isinstance(data, str):
            payload_data = data
        elif hasattr(data, "model_dump_json"):
            payload_data = data.model_dump_json()
        else:
            payload_data = json.dumps(data)

        payload = {"event": event, "data": payload_data}
        for q in list(self._subscribers):
            try:
                q.put_nowait(payload)
            except asyncio.QueueFull:
                try:
                    q.get_nowait()
                    q.put_nowait(payload)
                except Exception:
                    pass

    async def broadcast_state(self, state: SystemState) -> None:
        self.latest_state = state
        await self.broadcast("state_update", state)

    async def broadcast_approval_request(self, approval: dict[str, Any] | str) -> None:
        await self.broadcast("approval_request", approval)


monitor_service = AgentMonitorService()
broadcaster = EventBroadcaster()
recorded_approvals: dict[str, Any] = {}
approval_hooks: list[Callable[[str, bool, str], Any]] = []

router = APIRouter()


@router.get("/health")
@router.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/api/agents", response_model=SystemState)
async def get_agents() -> SystemState:
    state = await asyncio.to_thread(monitor_service.get_system_state)
    broadcaster.latest_state = state
    return state


@router.get("/api/events")
async def events(
    request: Request,
    count: int | None = None,
    limit: int | None = None,
) -> EventSourceResponse:
    # ponytail: optional count/limit query param enables finite reads in synchronous test harnesses
    max_events = count if count is not None else limit

    async def event_generator():
        q = broadcaster.subscribe()
        yielded = 0
        try:
            # Yield initial snapshot immediately
            state = broadcaster.latest_state
            if state is None:
                state = await asyncio.to_thread(monitor_service.get_system_state)
                broadcaster.latest_state = state

            yield {
                "event": "state_update",
                "data": state.model_dump_json(),
            }
            yielded += 1
            if max_events is not None and yielded >= max_events:
                return

            while True:
                if await request.is_disconnected():
                    break
                try:
                    event = await asyncio.wait_for(q.get(), timeout=1.0)
                    yield event
                    yielded += 1
                    if max_events is not None and yielded >= max_events:
                        break
                except asyncio.TimeoutError:
                    if max_events is not None:
                        break
                    continue
        finally:
            broadcaster.unsubscribe(q)

    return EventSourceResponse(event_generator())


@router.post("/api/approvals/{approval_id}")
async def submit_approval(
    approval_id: str,
    payload: ApprovalPayload | None = None,
) -> dict[str, str]:
    approved = payload.approved if payload else True
    reason = payload.reason if payload else ""
    recorded_approvals[approval_id] = {
        "approved": approved,
        "reason": reason,
    }
    for hook in approval_hooks:
        try:
            hook(approval_id, approved, reason)
        except Exception as e:
            logger.warning(f"Error executing approval hook: {e}")
    return {"status": "recorded"}
