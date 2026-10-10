.PHONY: help daemon web dev tunnel tunnel-cf tunnel-ts test build

BUN ?= $(shell command -v bun 2>/dev/null || echo $(HOME)/.bun/bin/bun)
UV ?= $(shell command -v uv 2>/dev/null || echo uv)
PORT ?= 8799

help:
	@echo "Mochi Hub Make commands:"
	@echo "  make dev        Jalankan daemon + web concurrent (Ctrl+C stop dua-duanya)"
	@echo "  make daemon     Jalankan backend Python daemon"
	@echo "  make web        Jalankan frontend Svelte 5 PWA"
	@echo "  make tunnel     Jalankan Cloudflare Tunnel (default)"
	@echo "  make tunnel-ts  Jalankan Tailscale Tunnel"
	@echo "  make build      Build static frontend web"
	@echo "  make test       Jalankan end-to-end verification"

daemon:
	cd hub/daemon && $(UV) run uvicorn mochi_daemon.main:app --port $(PORT) --reload

web:
	cd hub/web && $(BUN) run dev

dev:
	@trap 'kill 0' SIGINT SIGTERM EXIT; \
	(cd hub/daemon && $(UV) run uvicorn mochi_daemon.main:app --port $(PORT) --reload) & \
	(cd hub/web && $(BUN) run dev) & \
	wait

tunnel: tunnel-cf

tunnel-cf:
	cd hub && ./tunnel.sh --cloudflare

tunnel-ts:
	cd hub && ./tunnel.sh --tailscale

build:
	cd hub/web && $(BUN) run build

test:
	bash hub/verify_hub.sh
