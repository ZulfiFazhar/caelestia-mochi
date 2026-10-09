# Mochi Hub

Autonomous multi-agent companion hub featuring a background monitoring daemon and a mobile-first Svelte 5 Progressive Web App (PWA).

## Architecture

- **Backend Daemon (`hub/daemon`)**: Python async service built with FastAPI, SSE (`sse-starlette`), and PTY session runner. Polls harness session states, monitors resource usage, broadcasts SSE events at `/api/events`, and handles tool approvals.
- **Frontend Dashboard (`hub/web`)**: Svelte 5 PWA styled with Tailwind CSS. Renders dynamic agent rosters, real-time Mochi companion expressions (`MochiBot` and `MiniMochi`), tool approval cards, and offline caching via Service Worker.
- **Remote Access Helper (`hub/tunnel.sh`)**: CLI helper supporting Cloudflare Tunnel (`cloudflared`) and Tailscale Serve (`tailscale`) for instant mobile pairing.

---

## Getting Started

### Prerequisites

- Python `>= 3.11` and [`uv`](https://docs.astral.sh/uv/)
- [Bun](https://bun.sh/) (or Node.js)
- Optional: [`cloudflared`](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) or [`tailscale`](https://tailscale.com/download) for remote mobile access

---

### 1. Running the Backend Daemon

Navigate to the daemon directory and start the server with `uv`:

```bash
cd hub/daemon
uv run mochi-daemon
```

Or via direct module invocation:

```bash
cd hub/daemon
uv run python -m mochi_daemon.main
```

The daemon listens on `http://0.0.0.0:8799`.

#### Verify Health & API:

```bash
# Health check
curl http://localhost:8799/health

# Agent state
curl http://localhost:8799/api/agents

# SSE stream test
curl -N http://localhost:8799/api/events
```

#### Authentication Token (Optional):

To secure the daemon API, configure `MOCHI_AUTH_TOKEN`:

```bash
export MOCHI_AUTH_TOKEN="your-secret-token"
uv run mochi-daemon
```

When set:
- `/health` remains open without credentials for healthchecks.
- All `/api/*` routes require `Authorization: Bearer <token>`.

```bash
curl -H "Authorization: Bearer your-secret-token" http://localhost:8799/api/agents
```

---

### 2. Running the Web Frontend

Navigate to `hub/web` to install dependencies and start the Vite dev server:

```bash
cd hub/web
bun install
bun run dev
```

The Vite dev server starts at `http://localhost:5173` and automatically proxies `/api` calls to `http://127.0.0.1:8799`.

#### Production Build & Preview:

```bash
# Build optimized static assets into dist/
bun run build

# Preview production build locally
bun run preview
```

---

### 3. Remote Tunnel & Phone Pairing

Use `hub/tunnel.sh` to expose the local service to external devices securely.

```bash
# Cloudflare Tunnel
./hub/tunnel.sh --cloudflare

# Tailscale Serve
./hub/tunnel.sh --tailscale

# Specify custom port (e.g. dev server port 5173)
./hub/tunnel.sh --cloudflare --port 5173
```

> **Security Note**: When exposing via public tunnel, define `MOCHI_AUTH_TOKEN="<token>"` to require Bearer authentication on all `/api/*` endpoints while keeping `/health` available.

#### Installing as PWA on Mobile Devices:

1. Copy the public tunnel URL provided by `cloudflared` or your Tailscale node address.
2. Open the URL on your mobile browser:
   - **iOS (Safari)**: Tap the Share button -> select **"Add to Home Screen"**.
   - **Android (Chrome)**: Tap the three dots menu or install banner -> select **"Install App"** or **"Add to Home Screen"**.
3. Launch **Mochi Hub** directly from your home screen. It will open full-screen in standalone mode with `#1a1b26` background and service worker offline caching.

---

### 4. PWA Features & Service Worker Strategy

- **Web Manifest (`manifest.webmanifest`)**: Standalone display mode, dark theme `#1a1b26`, responsive icons.
- **Service Worker (`sw.js`)**:
  - **Cache-First**: Static shell assets (`index.html`, scripts, styles, SVGs, icons).
  - **Network-First**: Dynamic `/api/` endpoints with fallback to cached responses when offline.
  - **Live Streams**: Non-GET mutations and SSE (`/api/events`) pass through unbuffered.

---

### 5. Running Tests

```bash
# Backend daemon tests
cd hub/daemon && uv run pytest

# Web unit tests
cd hub/web && bun test

# Frontend build verification
cd hub/web && bun run build
```
