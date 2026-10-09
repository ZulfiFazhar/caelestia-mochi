#!/usr/bin/env bash
# ponytail: lightweight end-to-end integration verification for mochi hub daemon and pwa frontend
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${PORT:-8799}"

# Ensure bun is in PATH if installed in user home
if ! command -v bun >/dev/null 2>&1; then
  if [[ -d "$HOME/.bun/bin" ]]; then
    export PATH="$HOME/.bun/bin:$PATH"
  fi
fi

TEMP_DIR="$(mktemp -d)"
LOG_FILE="$TEMP_DIR/daemon.log"
DAEMON_PID=""

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ -n "${DAEMON_PID:-}" ]] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "Tearing down daemon (PID $DAEMON_PID)..."
    local child_pids
    child_pids=$(pgrep -P "$DAEMON_PID" 2>/dev/null || true)
    kill "$DAEMON_PID" 2>/dev/null || true
    for cpid in $child_pids; do
      kill "$cpid" 2>/dev/null || true
    done
    for _ in {1..20}; do
      if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$DAEMON_PID" 2>/dev/null; then
      kill -9 "$DAEMON_PID" 2>/dev/null || true
    fi
    for cpid in $child_pids; do
      if kill -0 "$cpid" 2>/dev/null; then
        kill -9 "$cpid" 2>/dev/null || true
      fi
    done
  fi
  if [[ -d "${TEMP_DIR:-}" ]]; then
    rm -rf "$TEMP_DIR"
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

echo "=== Mochi Hub Integration Verification ==="

# 1. Verify environments
echo "[1/6] Verifying runtime environments..."
if ! command -v uv >/dev/null 2>&1; then
  echo -e "${RED}Error: 'uv' not found in PATH.${NC}" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} uv found: $(uv --version)"

if ! command -v bun >/dev/null 2>&1; then
  echo -e "${RED}Error: 'bun' not found in PATH.${NC}" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} bun found: $(bun --version)"

if ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}Error: 'curl' not found in PATH.${NC}" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} curl found: $(curl --version | head -n 1)"

# 2. Build frontend assets
echo "[2/6] Building frontend assets in hub/web..."
(cd "$REPO_ROOT/hub/web" && bun run build)
if [[ ! -f "$REPO_ROOT/hub/web/dist/index.html" ]]; then
  echo -e "${RED}Error: Frontend build artifact dist/index.html missing.${NC}" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Frontend build succeeded."

# 3. Start daemon in background
echo "[3/6] Starting daemon on port $PORT..."
uv --directory "$REPO_ROOT/hub/daemon" run uvicorn mochi_daemon.main:app --port "$PORT" --host 127.0.0.1 > "$LOG_FILE" 2>&1 &
DAEMON_PID=$!

# 4. Poll /health until ready
echo "[4/6] Waiting for daemon health check..."
READY=false
for _ in {1..30}; do
  if curl -s -f "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    READY=true
    break
  fi
  if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo -e "${RED}Error: Daemon process exited prematurely.${NC}" >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi
  sleep 0.3
done

if [[ "$READY" != "true" ]]; then
  echo -e "${RED}Error: Daemon failed to become healthy within timeout.${NC}" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Daemon healthy."

# 5. Verify API endpoints
echo "[5/6] Verifying API endpoints..."
# Test GET /api/agents
AGENTS_JSON=$(curl -s -f "http://127.0.0.1:${PORT}/api/agents")
python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert 'agents' in data, 'Missing agents key in /api/agents'
assert 'mochi_state' in data, 'Missing mochi_state key in /api/agents'
" "$AGENTS_JSON"
echo -e "  ${GREEN}✓${NC} GET /api/agents valid (contains 'agents' and 'mochi_state')."

# Test GET /api/events SSE
SSE_OUTPUT=$(curl -s -N --max-time 3 "http://127.0.0.1:${PORT}/api/events?count=1")
if [[ "$SSE_OUTPUT" != *"state_update"* ]]; then
  echo -e "${RED}Error: SSE /api/events did not emit state_update.${NC}" >&2
  echo "Output was: $SSE_OUTPUT" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} GET /api/events?count=1 SSE stream validated."

# Test POST /api/approvals/test-app-1
APPROVAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"approved": true}' \
  "http://127.0.0.1:${PORT}/api/approvals/test-app-1")

if [[ "$APPROVAL_STATUS" != "200" ]]; then
  echo -e "${RED}Error: POST /api/approvals/test-app-1 returned HTTP $APPROVAL_STATUS (expected 200).${NC}" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} POST /api/approvals/test-app-1 returned HTTP 200."

# 6. Success
echo "[6/6] All integration checks passed!"
echo -e "${GREEN}✓ Mochi Hub End-to-End Verification SUCCESS${NC}"
exit 0
