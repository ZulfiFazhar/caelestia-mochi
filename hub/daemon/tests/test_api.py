import asyncio
import json
import pytest
from fastapi.testclient import TestClient
from mochi_daemon.api import (
    ApprovalPayload,
    approval_hooks,
    broadcaster,
    recorded_approvals,
)
from mochi_daemon.main import app, lifespan, poll_state_loop
from mochi_daemon.models import SystemState

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
    assert "timestamp" in data


def test_post_approval_no_body():
    response = client.post("/api/approvals/appr-001")
    assert response.status_code == 200
    assert response.json() == {"status": "recorded"}
    assert recorded_approvals["appr-001"]["approved"] is True


def test_post_approval_with_body():
    hook_called = []

    def hook(appr_id: str, approved: bool, reason: str):
        hook_called.append((appr_id, approved, reason))

    approval_hooks.append(hook)
    try:
        response = client.post(
            "/api/approvals/appr-002",
            json={"approved": False, "reason": "user rejected"},
        )
        assert response.status_code == 200
        assert response.json() == {"status": "recorded"}
        assert recorded_approvals["appr-002"]["approved"] is False
        assert recorded_approvals["appr-002"]["reason"] == "user rejected"
        assert len(hook_called) == 1
        assert hook_called[0] == ("appr-002", False, "user rejected")
    finally:
        approval_hooks.remove(hook)


def test_cors_headers():
    response = client.options(
        "/api/agents",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") in ("*", "http://localhost:5173")
    assert "access-control-allow-credentials" not in response.headers


def test_events_stream_state_update():
    with client.stream("GET", "/api/events?count=1") as response:
        assert response.status_code == 200
        assert "text/event-stream" in response.headers.get("content-type", "")
        lines = [line for line in response.iter_lines() if line]
        assert any("event: state_update" in l for l in lines)
        data_lines = [l for l in lines if l.startswith("data:")]
        assert len(data_lines) > 0
        parsed = json.loads(data_lines[0].replace("data:", "").strip())
        assert "mochi_state" in parsed


@pytest.mark.asyncio
async def test_broadcaster_event_dispatch():
    q = broadcaster.subscribe()
    try:
        await broadcaster.broadcast_approval_request({
            "approval_id": "appr-test",
            "command": "rm -rf /tmp/junk",
        })
        event = q.get_nowait()
        assert event["event"] == "approval_request"
        data = json.loads(event["data"])
        assert data["approval_id"] == "appr-test"
    finally:
        broadcaster.unsubscribe(q)


@pytest.mark.asyncio
async def test_broadcaster_queue_overflow_drop():
    # Verify queue does not crash when filled
    q = broadcaster.subscribe()
    try:
        for i in range(150):
            await broadcaster.broadcast("test_event", {"idx": i})
        assert q.qsize() <= 100
    finally:
        broadcaster.unsubscribe(q)


@pytest.mark.asyncio
async def test_lifespan_context():
    async with lifespan(app):
        # Allow loop to tick briefly
        await asyncio.sleep(0.05)
    # Exited cleanly without exception


def test_auth_token_protection(monkeypatch):
    # Set MOCHI_AUTH_TOKEN
    monkeypatch.setenv("MOCHI_AUTH_TOKEN", "supersecret123")

    # /health stays open
    health_resp = client.get("/health")
    assert health_resp.status_code == 200

    # /api/* requires token
    unauth_resp = client.get("/api/agents")
    assert unauth_resp.status_code == 401

    wrong_resp = client.get("/api/agents", headers={"Authorization": "Bearer wrongtoken"})
    assert wrong_resp.status_code == 401

    # Valid Bearer token
    ok_resp = client.get("/api/agents", headers={"Authorization": "Bearer supersecret123"})
    assert ok_resp.status_code == 200

    # Query token fallback
    query_ok = client.get("/api/agents?token=supersecret123")
    assert query_ok.status_code == 200

    # OPTIONS preflight stays open
    opt_resp = client.options("/api/agents", headers={"Origin": "http://localhost:5173", "Access-Control-Request-Method": "GET"})
    assert opt_resp.status_code == 200


def test_session_spawn_and_input_endpoints():
    import sys
    # Test POST /api/sessions
    spawn_resp = client.post("/api/sessions", json={"command": [sys.executable, "-c", "input(); print('done')"]})
    assert spawn_resp.status_code == 200
    data = spawn_resp.json()
    assert "session_id" in data
    assert data["status"] == "spawned"
    session_id = data["session_id"]

    # Test GET /api/sessions and GET /api/sessions/{session_id}
    list_resp = client.get("/api/sessions")
    assert list_resp.status_code == 200
    assert any(s["session_id"] == session_id for s in list_resp.json())

    get_resp = client.get(f"/api/sessions/{session_id}")
    assert get_resp.status_code == 200
    assert get_resp.json()["session_id"] == session_id

    # Test POST /api/sessions/{session_id}/input
    input_resp = client.post(f"/api/sessions/{session_id}/input", json={"data": "hello\n"})
    assert input_resp.status_code == 200
    assert input_resp.json() == {"status": "ok"}

    # Test 404 for input on non-existent session
    bad_resp = client.post("/api/sessions/nonexistent-session/input", json={"data": "hi"})
    assert bad_resp.status_code == 404
