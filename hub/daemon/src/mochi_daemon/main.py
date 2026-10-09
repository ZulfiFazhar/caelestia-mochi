from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from mochi_daemon.api import broadcaster, monitor_service, router

logger = logging.getLogger(__name__)


async def poll_state_loop(poll_interval: float = 1.0) -> None:
    while True:
        try:
            # ponytail: get_system_state offloaded to worker thread to avoid blocking asyncio loop
            state = await asyncio.to_thread(monitor_service.get_system_state)
            await broadcaster.broadcast_state(state)
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.warning(f"Error polling system state: {e}")
        await asyncio.sleep(poll_interval)


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(poll_state_loop(poll_interval=1.0))
    try:
        yield
    finally:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


def create_app() -> FastAPI:
    app = FastAPI(
        title="Mochi Hub Daemon",
        description="Backend daemon for Caelestia Mochi companion hub",
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(router)
    return app


app = create_app()


def main() -> None:
    import uvicorn

    uvicorn.run("mochi_daemon.main:app", host="0.0.0.0", port=8799, reload=False)


if __name__ == "__main__":
    main()
