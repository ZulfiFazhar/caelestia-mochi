import asyncio
import os
import signal
import sys
import time
import pytest

from mochi_daemon.session_runner import PtySessionManager
from mochi_daemon.api import EventBroadcaster


def test_pty_spawn_and_read():
    mgr = PtySessionManager()
    session_id = mgr.spawn_session(["echo", "hello mochi"])
    time.sleep(0.2)
    output = mgr.get_output(session_id)
    assert "hello mochi" in output
    mgr.terminate_session(session_id)


def test_pty_send_input():
    mgr = PtySessionManager()
    # Use python interactive or cat to echo input back
    session_id = mgr.spawn_session([sys.executable, "-c", "name = input(); print(f'got: {name}')"])
    time.sleep(0.1)
    mgr.send_input(session_id, "mochi-tester\n")
    time.sleep(0.2)
    output = mgr.get_output(session_id)
    assert "got: mochi-tester" in output
    mgr.terminate_session(session_id)


def test_pty_approval_detection_and_submit():
    approvals_captured = []

    def on_approval(req):
        approvals_captured.append(req)

    mgr = PtySessionManager(on_approval=on_approval)
    # Python script printing approval prompt then reading response
    script = (
        "import sys\n"
        "print('Do you approve this action? [y/N]: ', end='', flush=True)\n"
        "ans = sys.stdin.readline().strip()\n"
        "print(f'result: {ans}', flush=True)\n"
        "sys.stdin.readline()\n"
    )
    session_id = mgr.spawn_session([sys.executable, "-u", "-c", script])

    # Wait for approval prompt detection
    deadline = time.time() + 3.0
    while time.time() < deadline and not approvals_captured:
        time.sleep(0.05)

    assert len(approvals_captured) == 1
    appr = approvals_captured[0]
    assert appr["session_id"] == session_id
    assert "approval_id" in appr
    assert "[y/N]" in appr["prompt"]

    # Submit approval True
    ok = mgr.submit_approval(appr["approval_id"], approved=True)
    assert ok is True

    # Wait for result to appear in output
    deadline = time.time() + 2.0
    while time.time() < deadline:
        output = mgr.get_output(session_id)
        if "result: y" in output:
            break
        time.sleep(0.05)

    assert "result: y" in mgr.get_output(session_id)
    mgr.terminate_session(session_id)


def test_pty_approval_with_allow_prompt():
    approvals_captured = []
    mgr = PtySessionManager(on_approval=lambda r: approvals_captured.append(r))
    script = (
        "import sys\n"
        "print('Action dangerous. Allow (a) / Deny (d): ', end='', flush=True)\n"
        "ans = sys.stdin.readline().strip()\n"
        "print(f'decision: {ans}', flush=True)\n"
        "sys.stdin.readline()\n"
    )
    session_id = mgr.spawn_session([sys.executable, "-u", "-c", script])

    deadline = time.time() + 3.0
    while time.time() < deadline and not approvals_captured:
        time.sleep(0.05)

    assert len(approvals_captured) == 1
    appr_id = approvals_captured[0]["approval_id"]

    # Submit approved=True -> sends 'a\n'
    mgr.submit_approval(appr_id, approved=True)

    deadline = time.time() + 2.0
    while time.time() < deadline:
        output = mgr.get_output(session_id)
        if "decision: a" in output:
            break
        time.sleep(0.05)

    assert "decision: a" in mgr.get_output(session_id)
    mgr.terminate_session(session_id)


def test_pty_session_cleanup():
    mgr = PtySessionManager()
    session_id = mgr.spawn_session(["sleep", "60"])
    session = mgr.get_session(session_id)
    assert session is not None
    pid = session["pid"]

    # Process should be alive
    assert os.kill(pid, 0) is None or True

    mgr.terminate_session(session_id)
    time.sleep(0.1)

    # Process should be dead
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


@pytest.mark.asyncio
async def test_pty_wire_event_broadcaster():
    broadcaster = EventBroadcaster()
    queue = broadcaster.subscribe()

    mgr = PtySessionManager(broadcaster=broadcaster)
    script = "import sys; print('Proceed? [y/N]: ', end='', flush=True); sys.stdin.readline()"
    session_id = mgr.spawn_session([sys.executable, "-u", "-c", script])

    try:
        # Wait for broadcast event
        event = await asyncio.wait_for(queue.get(), timeout=3.0)
        assert event["event"] == "approval_request"
        data = event["data"]
        assert "approval_id" in data
        assert session_id in data
    finally:
        broadcaster.unsubscribe(queue)
        mgr.terminate_session(session_id)


def test_full_api_approval_integration():
    from mochi_daemon.api import session_manager
    from mochi_daemon.main import app
    from fastapi.testclient import TestClient

    test_client = TestClient(app)
    script = (
        "import sys\n"
        "print('Dangerous operation: Proceed? [y/N]: ', end='', flush=True)\n"
        "ans = sys.stdin.readline().strip()\n"
        "print(f'api_result: {ans}', flush=True)\n"
        "sys.stdin.readline()\n"
    )
    session_id = session_manager.spawn_session([sys.executable, "-u", "-c", script])

    deadline = time.time() + 3.0
    appr_id = None
    while time.time() < deadline:
        pending = session_manager.list_pending_approvals()
        for p in pending:
            if p["session_id"] == session_id:
                appr_id = p["approval_id"]
                break
        if appr_id:
            break
        time.sleep(0.05)

    assert appr_id is not None

    resp = test_client.post(f"/api/approvals/{appr_id}", json={"approved": True})
    assert resp.status_code == 200
    assert resp.json() == {"status": "recorded"}

    deadline = time.time() + 2.0
    while time.time() < deadline:
        output = session_manager.get_output(session_id)
        if "api_result: y" in output:
            break
        time.sleep(0.05)

    assert "api_result: y" in session_manager.get_output(session_id)
    session_manager.terminate_session(session_id)


def test_edge_cases_and_error_handling():
    mgr = PtySessionManager()

    # Unknown session
    with pytest.raises(KeyError):
        mgr.get_output("nonexistent")
    with pytest.raises(KeyError):
        mgr.send_input("nonexistent", "hello")
    assert mgr.get_session("nonexistent") is None

    # Invalid approval
    assert mgr.submit_approval("nonexistent", approved=True) is False

    # Spawn invalid command cleans up without leaking FDs
    with pytest.raises(FileNotFoundError):
        mgr.spawn_session(["nonexistent_executable_12345"])

    # Double terminate is safe
    session_id = mgr.spawn_session(["echo", "quick"])
    time.sleep(0.1)
    mgr.terminate_session(session_id)
    mgr.terminate_session(session_id)  # Idempotent call


def test_approval_auto_timeout():
    approvals_captured = []
    # Configure 0.3s approval timeout
    mgr = PtySessionManager(on_approval=lambda r: approvals_captured.append(r), approval_timeout=0.3)
    script = (
        "import sys\n"
        "print('Timeout test: Approve? [y/N]: ', end='', flush=True)\n"
        "ans = sys.stdin.readline().strip()\n"
        "print(f'timeout_result: {ans}', flush=True)\n"
    )
    session_id = mgr.spawn_session([sys.executable, "-u", "-c", script])

    deadline = time.time() + 3.0
    while time.time() < deadline and not approvals_captured:
        time.sleep(0.05)

    assert len(approvals_captured) == 1
    appr_id = approvals_captured[0]["approval_id"]

    # Wait for timeout to fire (0.3s + small buffer)
    time.sleep(0.5)

    # Check that approval was resolved and denied
    appr = mgr.get_approval(appr_id)
    assert appr is not None
    assert appr["resolved"] is True
    assert appr["approved"] is False

    # Check output from session: auto-deny sends 'n'
    output = mgr.get_output(session_id)
    assert "timeout_result: n" in output
    mgr.terminate_session(session_id)

