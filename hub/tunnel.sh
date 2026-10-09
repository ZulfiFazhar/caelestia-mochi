#!/usr/bin/env bash
# ponytail: bash tunnel wrapper; cloudflared or tailscale serve on target port
set -euo pipefail

DEFAULT_PORT=8799
PORT="${PORT:-$DEFAULT_PORT}"
MODE=""

print_usage() {
  cat << 'EOF'
Usage: ./hub/tunnel.sh [MODE] [OPTIONS]

Expose Mochi Hub dashboard and API to mobile devices via secure tunnel.

Modes:
  -c, --cloudflare    Start Cloudflare Tunnel (cloudflared)
  -t, --tailscale     Start Tailscale Serve background proxy

Options:
  -p, --port <port>   Local port to expose (default: 8799)
  -h, --help          Show this help message

Environment Variables:
  MOCHI_AUTH_TOKEN    Optional bearer token required on /api/* routes (/health stays open)

Examples:
  ./hub/tunnel.sh --cloudflare
  ./hub/tunnel.sh --tailscale
  ./hub/tunnel.sh --cloudflare --port 8799
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--cloudflare)
      MODE="cloudflare"
      shift
      ;;
    -t|--tailscale)
      MODE="tailscale"
      shift
      ;;
    -p|--port)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --port requires an argument" >&2
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Error: Must specify tunnel mode: --cloudflare or --tailscale" >&2
  echo "" >&2
  print_usage
  exit 1
fi

if [[ -n "${MOCHI_AUTH_TOKEN:-}" ]]; then
  echo "Auth: MOCHI_AUTH_TOKEN is active. Remote clients must provide Bearer authentication."
else
  echo "Security Note: MOCHI_AUTH_TOKEN is unset. Set MOCHI_AUTH_TOKEN to secure /api/* endpoints."
fi

if [[ "$MODE" == "cloudflare" ]]; then
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "Error: 'cloudflared' command not found in PATH." >&2
    echo "Install cloudflared: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" >&2
    exit 1
  fi
  echo "Starting Cloudflare tunnel to http://localhost:${PORT}..."
  exec cloudflared tunnel --url "http://localhost:${PORT}"
elif [[ "$MODE" == "tailscale" ]]; then
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "Error: 'tailscale' command not found in PATH." >&2
    echo "Install tailscale: https://tailscale.com/download" >&2
    exit 1
  fi
  echo "Enabling Tailscale serve for port ${PORT}..."
  exec tailscale serve --bg "${PORT}"
fi
