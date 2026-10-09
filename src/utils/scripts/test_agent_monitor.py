#!/usr/bin/env python3
import subprocess
import json
import sys
import importlib.util
from pathlib import Path

script_path = Path(__file__).parent / "agent_monitor.py"
proc = subprocess.run([sys.executable, str(script_path)], capture_output=True, text=True, check=True)
data = json.loads(proc.stdout)

assert isinstance(data, dict), "data must be dict"
assert "agents" in data, "data must contain 'agents'"
assert "installed_harnesses" in data, "data must contain 'installed_harnesses'"
assert isinstance(data["agents"], list), "'agents' must be a list"
assert isinstance(data["installed_harnesses"], list), "'installed_harnesses' must be a list"

for item in data["agents"]:
    for key in ("id", "name", "icon", "color", "installed", "bin", "running", "count", "pid", "cpu", "mem", "etime", "activity", "window_address", "workspace_id", "instances", "mochi"):
        assert key in item, f"missing key {key} in {item}"
    assert "emoji" in item["mochi"] and "state" in item["mochi"]
    for inst in item["instances"]:
        assert "mochi" in inst, f"missing mochi in instance {inst}"
        assert "emoji" in inst["mochi"] and "state" in inst["mochi"]

for item in data["installed_harnesses"]:
    for key in ("id", "name", "icon", "color", "bin", "path", "running", "count"):
        assert key in item, f"missing key {key} in {item}"

# Unit logic verification
spec = importlib.util.spec_from_file_location("agent_monitor", script_path)
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)

# Test idle fallback threshold
idle_mochi = monitor.get_mochi_state("other_agent", 999999, 0.4, False, "other_agent", "Terminal", True)
assert idle_mochi["state"] == "idle", f"Expected idle, got {idle_mochi}"

# Test working threshold
work_mochi = monitor.get_mochi_state("other_agent", 999999, 12.0, False, "other_agent", "Terminal", True)
assert work_mochi["state"] == "working", f"Expected working, got {work_mochi}"

# Test thinking threshold
think_mochi = monitor.get_mochi_state("other_agent", 999999, 3.2, False, "other_agent", "Terminal", True)
assert think_mochi["state"] == "thinking", f"Expected thinking, got {think_mochi}"

# Test sleeping threshold
sleep_mochi = monitor.get_mochi_state("other_agent", 999999, 0.0, False, "other_agent", "Terminal", False)
assert sleep_mochi["state"] == "sleeping", f"Expected sleeping, got {sleep_mochi}"

print("OK")
