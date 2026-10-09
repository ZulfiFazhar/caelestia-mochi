import json
import sqlite3
import time
from pathlib import Path
import pytest

from mochi_daemon.models import AgentInfo, MochiState, SystemState
from mochi_daemon.monitor import AgentMonitorService, STATE_PRIORITY


def test_monitor_service_returns_valid_state():
    service = AgentMonitorService()
    state = service.get_system_state()
    assert isinstance(state, SystemState)
    assert isinstance(state.mochi_state, MochiState)
    assert isinstance(state.agents, list)


def test_mochi_state_enum_and_aliases():
    assert MochiState("sleeping") == MochiState.SLEEPING
    assert MochiState("idle") == MochiState.IDLE
    assert MochiState("thinking") == MochiState.THINKING
    assert MochiState("working") == MochiState.WORKING
    assert MochiState("searching") == MochiState.SEARCHING
    assert MochiState("approval") == MochiState.APPROVAL
    assert MochiState("question") == MochiState.QUESTION
    assert MochiState("done") == MochiState.DONE
    # Alias mapping
    assert MochiState("finished") == MochiState.DONE
    assert MochiState("complete") == MochiState.DONE
    assert MochiState("completed") == MochiState.DONE


def test_models_serialization():
    agent = AgentInfo(
        name="TestAgent",
        command="test",
        pid=1234,
        status="working",
        cpu=12.5,
        memory=3.2,
        details={"running": True},
    )
    assert agent.name == "TestAgent"
    assert agent.pid == 1234
    assert agent.cpu == 12.5

    state = SystemState(
        timestamp=1700000000.0,
        agents=[agent],
        active_agent=agent,
        mochi_state=MochiState.WORKING,
    )
    dump = state.model_dump()
    assert dump["timestamp"] == 1700000000.0
    assert len(dump["agents"]) == 1
    assert dump["mochi_state"] == "working"
    assert dump["active_agent"]["name"] == "TestAgent"


def test_opencode_db_inspection(tmp_path: Path):
    db_file = tmp_path / "opencode.db"
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("CREATE TABLE session_v2 (id TEXT, title TEXT, directory TEXT, time_updated INTEGER)")
    cur.execute("CREATE TABLE session_message (session_id TEXT, time_created INTEGER, data TEXT)")

    # Insert test session
    cur.execute("INSERT INTO session_v2 VALUES (?, ?, ?, ?)", ("s1", "My Session", "/tmp/proj", 1000))
    # Test reasoning state
    msg_reasoning = json.dumps({"content": [{"type": "reasoning"}]})
    cur.execute("INSERT INTO session_message VALUES (?, ?, ?)", ("s1", 1000, msg_reasoning))
    conn.commit()
    conn.close()

    service = AgentMonitorService(db_path=str(db_file))
    # Inspect with title matching "OC | My Session"
    st = service.inspect_opencode_db(pid=0, title="OC | My Session")
    assert st == MochiState.THINKING

    # Test tool question
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    msg_tool_question = json.dumps({
        "content": [{"type": "tool", "name": "question", "state": {"status": "running"}}]
    })
    cur.execute("UPDATE session_message SET data = ? WHERE session_id = 's1'", (msg_tool_question,))
    conn.commit()
    conn.close()

    st = service.inspect_opencode_db(pid=0, title="OC | My Session")
    assert st == MochiState.QUESTION

    # Test outcome completed recently
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    msg_outcome = json.dumps({
        "outcome": "success",
        "time": {"created": int(time.time() * 1000)},
    })
    cur.execute("UPDATE session_message SET data = ? WHERE session_id = 's1'", (msg_outcome,))
    conn.commit()
    conn.close()

    st = service.inspect_opencode_db(pid=0, title="OC | My Session")
    assert st == MochiState.DONE


def test_state_priority_ordering():
    assert STATE_PRIORITY[MochiState.APPROVAL] > STATE_PRIORITY[MochiState.QUESTION]
    assert STATE_PRIORITY[MochiState.QUESTION] > STATE_PRIORITY[MochiState.WORKING]
    assert STATE_PRIORITY[MochiState.WORKING] > STATE_PRIORITY[MochiState.SEARCHING]
    assert STATE_PRIORITY[MochiState.SEARCHING] > STATE_PRIORITY[MochiState.THINKING]
    assert STATE_PRIORITY[MochiState.THINKING] > STATE_PRIORITY[MochiState.DONE]
    assert STATE_PRIORITY[MochiState.DONE] > STATE_PRIORITY[MochiState.IDLE]
    assert STATE_PRIORITY[MochiState.IDLE] > STATE_PRIORITY[MochiState.SLEEPING]


def test_determine_instance_state():
    service = AgentMonitorService()
    # sleeping when not running
    assert service._determine_instance_state("test", 1, 0.0, False, "test", "", False) == MochiState.SLEEPING

    # text pattern: approval
    assert service._determine_instance_state("test", 1, 0.0, False, "test [y/n]", "", True) == MochiState.APPROVAL
    # text pattern: searching
    assert service._determine_instance_state("test", 1, 0.0, False, "grep pattern", "", True) == MochiState.SEARCHING
    # text pattern: question
    assert service._determine_instance_state("test", 1, 0.0, False, "ask user", "", True) == MochiState.QUESTION
    # text pattern: done
    assert service._determine_instance_state("test", 1, 0.0, False, "task complete", "", True) == MochiState.DONE

    # CPU activity
    assert service._determine_instance_state("test", 1, 10.0, False, "run", "", True) == MochiState.WORKING
    assert service._determine_instance_state("test", 1, 2.0, False, "run", "", True) == MochiState.THINKING
    assert service._determine_instance_state("test", 1, 0.1, False, "run", "", True) == MochiState.IDLE


def test_tick_delta_calculation():
    service = AgentMonitorService()
    now = time.time()
    service._tick_cache["9999"] = {"ticks": 1000, "time": now - 1.0}
    prev = service._tick_cache["9999"]
    dt = max(0.001, now - prev["time"])
    dticks = max(0, 1100 - prev["ticks"])
    inst_cpu = (dticks / 100.0) / dt * 100.0
    assert pytest.approx(inst_cpu, rel=1e-2) == 100.0


def test_descendants_cycle_handling():
    service = AgentMonitorService()
    # Cyclic parent map should not cause infinite loop or crash
    parent_map = {101: 102, 102: 101, 103: 101}
    desc = service._get_descendants(101, parent_map)
    assert 102 in desc
    assert 103 in desc

