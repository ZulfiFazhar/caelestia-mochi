# Mochi Hub PWA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Mochi Hub — a remote-accessible PWA and agent orchestrator for Caelestia Shell featuring an animated Mochi companion, real-time harness monitoring, terminal session streaming, and remote approval handling.

**Architecture:** A lightweight Python async daemon managed via `uv` runs on the host to monitor harnesses, manage pseudo-terminals (PTY), and stream events over REST/SSE. A mobile-first Svelte 5 PWA bundled via `bun` connects locally or over a secure tunnel (Tailscale/Cloudflare) to deliver real-time Mochi expressions, agent status, and interactive approval cards.

**Tech Stack:** 
- Backend: Python 3.14, `uv`, `pyproject.toml`, FastAPI, uvicorn, sse-starlette, pty
- Frontend: Svelte 5 (Runes), TypeScript, Tailwind CSS, Vite, `bun`
- Tunneling: Cloudflare Tunnel (`cloudflared`) / Tailscale Funnel

**Spec:** `/home/zulfi/Projects/caelestia-mochi/README.md` and design discussion in session.

## Global Constraints

- Backend must use `uv` and `pyproject.toml` (no loose pip requirements).
- Frontend must use `bun` as package manager and runtime.
- Re-use existing instantaneous CPU tick calculations and SQLite logic from `src/utils/scripts/agent_monitor.py`.
- Mochi visual expressions in Svelte must faithfully replicate the 6 eye shapes (`pill`, `wide`, `happy`, `closed`, `flat`, `dizzy`) and colors from `src/modules/dashboard/agent/MochiBot.qml`.
- Idempotent and clean git structure under `hub/` inside `/home/zulfi/Projects/caelestia-mochi`.

## Review Focus

1. **PTY Session Cleanup:** Ensure child processes spawned via PTY terminate cleanly without leaving orphaned processes.
2. **SSE Connection Drop & Reconnect:** Client must gracefully handle network disconnects and reconnect without duplicating event handlers.
3. **Approval Timeout:** Approval requests pending user input must expire gracefully if not acknowledged within a configured time limit.
4. **Mobile Responsive Touch:** Mochi gaze and squish interactions must respond properly to mobile touch events (`touchstart`, `touchmove`, `touchend`) without scrolling lockouts.
5. **CORS / Security Boundary:** Ensure API rejects unauthenticated requests when exposed to remote networks unless authorized by bearer token.

---

### Task 1: Backend Daemon Environment & Monitor Service (`uv` + `pyproject.toml`)

**Files:**
- Create: `hub/daemon/pyproject.toml`
- Create: `hub/daemon/src/mochi_daemon/models.py`
- Create: `hub/daemon/src/mochi_daemon/monitor.py`
- Test: `hub/daemon/tests/test_monitor.py`

**Interfaces:**
- Produces: `AgentMonitorService.get_system_state() -> SystemState`
- Models: `AgentInfo(name, command, pid, status, cpu, memory, details)`, `SystemState(timestamp, agents, active_agent, mochi_state)`

- [ ] **Step 1: Write the failing test for `AgentMonitorService`**

```python
# hub/daemon/tests/test_monitor.py
import pytest
from mochi_daemon.models import SystemState, MochiState
from mochi_daemon.monitor import AgentMonitorService

def test_monitor_service_returns_valid_state():
    service = AgentMonitorService()
    state = service.get_system_state()
    assert isinstance(state, SystemState)
    assert isinstance(state.mochi_state, MochiState)
    assert isinstance(state.agents, list)
```

- [ ] **Step 2: Initialize `hub/daemon/pyproject.toml` with `uv`**

```toml
[project]
name = "mochi-daemon"
version = "0.1.0"
description = "Mochi Hub backend daemon"
readme = "README.md"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.115.0",
    "uvicorn>=0.30.0",
    "pydantic>=2.8.0",
    "sse-starlette>=2.1.0",
]

[dependency-groups]
dev = [
    "pytest>=8.0.0",
    "pytest-asyncio>=0.23.0",
    "httpx>=0.27.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

Run: `cd hub/daemon && uv sync`
Run: `uv run pytest tests/test_monitor.py`
Expected: FAIL (module `mochi_daemon` not found).

- [ ] **Step 3: Implement data models in `hub/daemon/src/mochi_daemon/models.py`**

Define `MochiState` enum (`sleeping`, `idle`, `thinking`, `working`, `searching`, `approval`, `question`, `done`), `AgentInfo`, and `SystemState` using Pydantic `BaseModel`.

- [ ] **Step 4: Implement `AgentMonitorService` in `hub/daemon/src/mochi_daemon/monitor.py`**

Import and adapt CPU tick delta calculation and OpenCode DB inspection logic from `src/utils/scripts/agent_monitor.py`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd hub/daemon && uv run pytest tests/test_monitor.py`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add hub/daemon
git commit -m "feat(hub): initialize daemon with uv and monitor service"
```

---

### Task 2: Backend REST & SSE Event Stream API

**Files:**
- Create: `hub/daemon/src/mochi_daemon/api.py`
- Create: `hub/daemon/src/mochi_daemon/main.py`
- Test: `hub/daemon/tests/test_api.py`

**Interfaces:**
- Consumes: `AgentMonitorService`
- Endpoints:
  - `GET /health` -> `{"status": "ok"}`
  - `GET /api/agents` -> `SystemState`
  - `GET /api/events` -> SSE stream (`event: state_update`, `event: approval_request`)
  - `POST /api/approvals/{approval_id}` -> `{"status": "recorded"}`

- [ ] **Step 1: Write the failing test for API endpoints**

```python
# hub/daemon/tests/test_api.py
import pytest
from fastapi.testclient import TestClient
from mochi_daemon.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_get_agents():
    response = client.get("/api/agents")
    assert response.status_code == 200
    data = response.json()
    assert "agents" in data
    assert "mochi_state" in data
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hub/daemon && uv run pytest tests/test_api.py`
Expected: FAIL (`mochi_daemon.main` not defined).

- [ ] **Step 3: Implement FastAPI routes in `api.py` and `main.py`**

Provide CORS middleware for local network & tunnel origins, background SSE broadcaster polling state every 1s, and approval submission endpoints.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hub/daemon && uv run pytest tests/test_api.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hub/daemon
git commit -m "feat(hub): implement REST and SSE endpoints"
```

---

### Task 3: PTY Session Runner & Approval Interceptor

**Files:**
- Create: `hub/daemon/src/mochi_daemon/session_runner.py`
- Test: `hub/daemon/tests/test_session_runner.py`

**Interfaces:**
- Produces: `PtySessionManager.spawn_session(command: list[str]) -> str (session_id)`
- Produces: `PtySessionManager.send_input(session_id: str, data: str)`
- Produces: `PtySessionManager.submit_approval(approval_id: str, approved: bool)`

- [ ] **Step 1: Write the failing test for PTY spawning and approval detection**

```python
# hub/daemon/tests/test_session_runner.py
import pytest, time
from mochi_daemon.session_runner import PtySessionManager

def test_pty_spawn_and_read():
    mgr = PtySessionManager()
    session_id = mgr.spawn_session(["echo", "hello mochi"])
    time.sleep(0.2)
    output = mgr.get_output(session_id)
    assert "hello mochi" in output
    mgr.terminate_session(session_id)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hub/daemon && uv run pytest tests/test_session_runner.py`
Expected: FAIL.

- [ ] **Step 3: Implement `PtySessionManager` using Python standard library `pty`, `os`, `select`**

Capture output streams in non-blocking loop, detect approval prompts (`[y/N]`, `Allow (a)`, `Approve?`), assign an `approval_id`, and broadcast to SSE bus.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hub/daemon && uv run pytest tests/test_session_runner.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hub/daemon
git commit -m "feat(hub): add pty session manager with approval detection"
```

---

### Task 4: Svelte 5 PWA Setup with `bun` & Tailwind CSS

**Files:**
- Create: `hub/web/package.json`
- Create: `hub/web/vite.config.ts`
- Create: `hub/web/src/app.css`
- Create: `hub/web/index.html`
- Create: `hub/web/src/main.ts`

**Interfaces:**
- Svelte 5 Runes (`$state`, `$derived`, `$effect`)
- Tailwind CSS styling matching Caelestia Material 3 tokens.

- [ ] **Step 1: Scaffold Svelte 5 project with `bun`**

```bash
cd hub
~/.bun/bin/bun create vite web --template svelte-ts
cd web
~/.bun/bin/bun add -d tailwindcss @tailwindcss/vite
```

- [ ] **Step 2: Configure Vite & Tailwind**

Update `hub/web/vite.config.ts` to include Tailwind Vite plugin and configure dev server proxy to `http://127.0.0.1:8799`.

- [ ] **Step 3: Test build with `bun`**

Run: `cd hub/web && ~/.bun/bin/bun run build`
Expected: Build succeeds with 0 errors.

- [ ] **Step 4: Commit**

```bash
git add hub/web
git commit -m "feat(hub): scaffold Svelte 5 PWA using bun and tailwind"
```

---

### Task 5: Reactive Mochi Companion Engine in Svelte 5

**Files:**
- Create: `hub/web/src/lib/types/agent.ts`
- Create: `hub/web/src/lib/components/MochiBot.svelte`
- Create: `hub/web/src/lib/components/MiniMochi.svelte`

**Interfaces:**
- Props: `state: MochiState`, `size?: number`, `interactive?: boolean`
- Behaviors:
  - Eye shape changes: `pill` (idle), `wide` (thinking), `happy` (done), `closed` (sleeping), `flat` (approval), `dizzy` (error/triple-tap).
  - Squish scale animation on tap/touch.
  - Cursor / touch gaze offset calculations.

- [ ] **Step 1: Define TypeScript types in `agent.ts`**

Define `MochiState`, `EyeShape`, `AgentInfo`, `ApprovalRequest`.

- [ ] **Step 2: Implement `MochiBot.svelte` with SVG / CSS Path rendering**

Port Bezier curves and eye physics from `src/modules/dashboard/agent/MochiBot.qml`.
Add pointer and touch tracking for dynamic eye pupils.
Add squish trigger on click/tap and easter-egg triple-tap dizzy mode.

- [ ] **Step 3: Implement `MiniMochi.svelte` micro avatar**

Compact 28px avatar component with reactive eye shapes for agent rows.

- [ ] **Step 4: Run build check**

Run: `cd hub/web && ~/.bun/bin/bun run build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hub/web/src/lib
git commit -m "feat(hub): implement reactive MochiBot and MiniMochi in Svelte 5"
```

---

### Task 6: PWA Realtime Store & Remote Agent Dashboard UI

**Files:**
- Create: `hub/web/src/lib/stores/agentStore.svelte.ts`
- Create: `hub/web/src/lib/components/AgentRoster.svelte`
- Create: `hub/web/src/lib/components/ApprovalCard.svelte`
- Create: `hub/web/src/lib/components/ChatTimeline.svelte`
- Modify: `hub/web/src/App.svelte`

**Interfaces:**
- Consumes: SSE `/api/events`, REST `/api/approvals/{id}`
- Produces: Complete reactive mobile UI.

- [ ] **Step 1: Implement Svelte 5 store in `agentStore.svelte.ts`**

Connect to `EventSource('/api/events')` with auto-reconnect backoff.
Store `$state` for `agents`, `mochiState`, `activeApproval`, and connection status.

- [ ] **Step 2: Implement `AgentRoster.svelte` and `ApprovalCard.svelte`**

Agent list with CPU/memory badges and MiniMochi indicators.
Prominent approval modal card with "Allow" (green) and "Deny" (red) buttons.

- [ ] **Step 3: Implement `ChatTimeline.svelte` and assemble in `App.svelte`**

Header featuring `MochiBot` companion.
Main section showing active terminal transcript or chat timeline.
Bottom bar with command input box and launch quick-actions.

- [ ] **Step 4: Verify build with `bun`**

Run: `cd hub/web && ~/.bun/bin/bun run build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hub/web/src
git commit -m "feat(hub): assemble full PWA dashboard and approval cards"
```

---

### Task 7: PWA Manifest, Service Worker & Remote Tunnel Helper

**Files:**
- Create: `hub/web/public/manifest.webmanifest`
- Create: `hub/web/public/sw.js`
- Create: `hub/tunnel.sh`
- Create: `hub/README.md`

**Interfaces:**
- PWA installable on Android / iOS home screen.
- Tunnel script supporting `--tailscale` and `--cloudflare`.

- [ ] **Step 1: Create `manifest.webmanifest` and Service Worker `sw.js`**

Set `name: "Mochi Hub"`, `display: "standalone"`, `theme_color: "#1a1b26"`.
Implement cache-first for static assets and network-first for `/api/`.

- [ ] **Step 2: Create `hub/tunnel.sh` helper**

Provide one-line tunnel start:
- Cloudflare: `cloudflared tunnel --url http://localhost:8799`
- Tailscale: `tailscale serve --bg 8799`

- [ ] **Step 3: Document usage in `hub/README.md`**

Explain `uv run` for daemon, `bun run dev` for web, and tunnel instructions.

- [ ] **Step 4: Commit**

```bash
git add hub/web/public hub/tunnel.sh hub/README.md
git commit -m "feat(hub): add PWA manifest, service worker, and tunnel helper"
```

---

### Task 8: End-to-End Verification & Integration Test

**Files:**
- Create: `hub/verify_hub.sh`

- [ ] **Step 1: Write `verify_hub.sh`**

Script starts daemon in background with `uv run`, builds web with `bun run build`, curls `/health` and `/api/agents`, validates JSON output, and tears down cleanly.

- [ ] **Step 2: Run verification script**

Run: `bash hub/verify_hub.sh`
Expected: All checks PASS with green exit code 0.

- [ ] **Step 3: Commit**

```bash
git add hub/verify_hub.sh
git commit -m "test(hub): add end-to-end integration verification script"
```
