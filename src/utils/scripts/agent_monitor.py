#!/usr/bin/env python3
import os
import json
import subprocess
import shutil
import re
import time
import sqlite3

targets = [
    {
        "id": "opencode",
        "name": "OpenCode",
        "icon": "terminal",
        "color": "#4ADE80",
        "bins": ["opencode"],
        "pattern": r"(^|[\s/])opencode(\s|$)"
    },
    {
        "id": "claude",
        "name": "Claude Code",
        "icon": "smart_toy",
        "color": "#D97757",
        "bins": ["claude", "claude-code"],
        "pattern": r"(^|[\s/])(claude|claude-code)(\s|$)"
    },
    {
        "id": "antigravity",
        "name": "Antigravity",
        "icon": "rocket_launch",
        "color": "#E879F9",
        "bins": ["antigravity", "agy"],
        "pattern": r"(^|[\s/])(antigravity|agy)(\s|$)"
    },
    {
        "id": "codex",
        "name": "Codex",
        "icon": "code",
        "color": "#2DD4BF",
        "bins": ["codex"],
        "pattern": r"(^|[\s/])codex(\s|$)"
    },
    {
        "id": "aider",
        "name": "Aider",
        "icon": "psychology",
        "color": "#38BDF8",
        "bins": ["aider"],
        "pattern": r"(^|[\s/])aider(\s|$)"
    },
    {
        "id": "cursor",
        "name": "Cursor",
        "icon": "edit_square",
        "color": "#818CF8",
        "bins": ["cursor", "cursor-agent"],
        "pattern": r"(^|[\s/])cursor(-agent)?(\s|$)"
    },
    {
        "id": "windsurf",
        "name": "Windsurf",
        "icon": "surfing",
        "color": "#06B6D4",
        "bins": ["windsurf"],
        "pattern": r"(^|[\s/])windsurf(\s|$)"
    },
    {
        "id": "goose",
        "name": "Goose AI",
        "icon": "flutter",
        "color": "#F59E0B",
        "bins": ["goose", "goose-ai"],
        "pattern": r"(^|[\s/])goose(-ai)?(\s|$)"
    },
    {
        "id": "plandex",
        "name": "Plandex",
        "icon": "alt_route",
        "color": "#EC4899",
        "bins": ["plandex"],
        "pattern": r"(^|[\s/])plandex(\s|$)"
    },
    {
        "id": "cline",
        "name": "Cline",
        "icon": "terminal",
        "color": "#10B981",
        "bins": ["cline"],
        "pattern": r"(^|[\s/])cline(\s|$)"
    },
    {
        "id": "continue",
        "name": "Continue",
        "icon": "fast_forward",
        "color": "#6366F1",
        "bins": ["continue"],
        "pattern": r"(^|[\s/])continue(\s|$)"
    },
]

# Check PATH and standard user bin locations
extra_paths = [
    os.path.expanduser("~/.local/bin"),
    os.path.expanduser("~/.cargo/bin"),
    os.path.expanduser("~/.bun/bin"),
    os.path.expanduser("~/.npm-global/bin"),
    "/usr/local/bin",
    "/usr/bin",
]
current_path = os.environ.get("PATH", "")
all_paths = ":".join([p for p in extra_paths if os.path.isdir(p)] + [current_path])

def check_bin(bin_names):
    for b in bin_names:
        p = shutil.which(b, path=all_paths)
        if p:
            return b, p
    return None, None

try:
    hypr_out = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
    hypr_clients = json.loads(hypr_out)
except Exception:
    hypr_clients = []

client_by_pid = {c.get("pid"): c for c in hypr_clients if c.get("pid")}

parent_map = {}
try:
    ps_tree = subprocess.check_output(["ps", "-eo", "pid,ppid"], text=True).splitlines()[1:]
    for line in ps_tree:
        parts = line.strip().split()
        if len(parts) == 2:
            parent_map[int(parts[0])] = int(parts[1])
except Exception:
    pass

def find_window(pid):
    curr = pid
    for _ in range(6):
        if curr in client_by_pid:
            return client_by_pid[curr]
        if curr in parent_map:
            curr = parent_map[curr]
        else:
            break
    return None

def get_descendants(pid):
    desc = []
    for child, parent in parent_map.items():
        if parent == pid:
            desc.append(child)
            desc.extend(get_descendants(child))
    return desc

def get_pid_ticks(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            fields = f.read().split()
            return int(fields[13]) + int(fields[14])
    except Exception:
        return 0

def get_tree_ticks(pid):
    ticks = get_pid_ticks(pid)
    for c in get_descendants(pid):
        ticks += get_pid_ticks(c)
    return ticks

# Persistent tick cache for real-time instantaneous CPU calculation
CACHE_FILE = "/tmp/caelestia_agent_ticks.json"
now_s = time.time()
tick_cache = {}
try:
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE, "r") as f:
            tick_cache = json.load(f)
except Exception:
    tick_cache = {}

STATE_DEFS = {
    "working": {"state": "working", "emoji": "⚡", "kaomoji": "(•̀ •́)", "label": "Working", "color": "#3B9EFF"},
    "thinking": {"state": "thinking", "emoji": "🤔", "kaomoji": "(• . •)", "label": "Thinking", "color": "#A78BFA"},
    "searching": {"state": "searching", "emoji": "🔍", "kaomoji": "(◉ ◉)", "label": "Searching", "color": "#6366F1"},
    "approval": {"state": "approval", "emoji": "⏳", "kaomoji": "(O O)!", "label": "Approval", "color": "#F5A524"},
    "question": {"state": "question", "emoji": "❓", "kaomoji": "(• o •)?", "label": "Question", "color": "#22D3EE"},
    "error": {"state": "error", "emoji": "💥", "kaomoji": "(- -)!", "label": "Error", "color": "#F4505E"},
    "finished": {"state": "finished", "emoji": "✨", "kaomoji": "(^ ‿ ^)", "label": "Done", "color": "#34D399"},
    "ratelimit": {"state": "ratelimit", "emoji": "🥵", "kaomoji": "(ｰ ｰ)💦", "label": "Rate Limit", "color": "#F59E0B"},
    "sleeping": {"state": "sleeping", "emoji": "💤", "kaomoji": "(- . -)zZ", "label": "Sleeping", "color": "#94A3B8"},
    "idle": {"state": "idle", "emoji": "🍙", "kaomoji": "(• •)", "label": "Idle", "color": "#CBD5E1"},
}

STATE_PRIORITY = {
    "error": 10,
    "approval": 9,
    "question": 8,
    "working": 7,
    "searching": 6,
    "thinking": 5,
    "finished": 4,
    "ratelimit": 3,
    "idle": 2,
    "sleeping": 1,
}

def inspect_opencode_db(pid, title):
    db_path = os.path.expanduser("~/.local/share/opencode/opencode.db")
    if not os.path.exists(db_path):
        return None
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        c = conn.cursor()

        # Find matching session
        sid = None
        if title and title.startswith("OC | "):
            stitle = title[5:].strip()
            # Try exact match or prefix
            c.execute("SELECT id FROM session_v2 WHERE title = ? ORDER BY time_updated DESC LIMIT 1", (stitle,))
            row = c.fetchone()
            if not row and len(stitle) > 10:
                c.execute("SELECT id FROM session_v2 WHERE title LIKE ? ORDER BY time_updated DESC LIMIT 1", (stitle[:20] + "%",))
                row = c.fetchone()
            if row:
                sid = row[0]

        if not sid:
            try:
                cwd = os.readlink(f"/proc/{pid}/cwd")
                c.execute("SELECT id FROM session_v2 WHERE directory = ? ORDER BY time_updated DESC LIMIT 1", (cwd,))
                row = c.fetchone()
                if row:
                    sid = row[0]
            except Exception:
                pass

        if not sid:
            return STATE_DEFS["idle"]

        # Check latest session message
        c.execute("SELECT data FROM session_message WHERE session_id = ? ORDER BY time_created DESC LIMIT 1", (sid,))
        row = c.fetchone()
        if not row:
            return STATE_DEFS["idle"]

        data = json.loads(row[0])
        now_ms = time.time() * 1000

        # Outcome indicates turn is complete
        if "outcome" in data:
            t_done = data.get("time", {}).get("created", 0)
            if now_ms - t_done < 15000:
                return STATE_DEFS["finished"]
            return STATE_DEFS["idle"]

        content = data.get("content", [])
        if content:
            last_item = content[-1]
            itype = last_item.get("type")
            if itype == "tool":
                tool_state = last_item.get("state", {})
                t_status = tool_state.get("status")
                tool_name = last_item.get("name", "")
                if t_status == "running" or not last_item.get("executed", True):
                    if tool_name == "question":
                        return STATE_DEFS["question"]
                    if tool_name in ("grep", "glob", "websearch", "webfetch"):
                        return STATE_DEFS["searching"]
                    return STATE_DEFS["working"]
            elif itype == "reasoning":
                return STATE_DEFS["thinking"]

        if data.get("agent") and not data.get("finish"):
            return STATE_DEFS["thinking"]

        return STATE_DEFS["idle"]
    except Exception:
        return None

def get_mochi_state(target_id, pid, inst_cpu, has_children, cmd, title, is_running):
    if not is_running:
        return STATE_DEFS["sleeping"]

    # 1. Native OpenCode inspection
    if target_id == "opencode":
        db_state = inspect_opencode_db(pid, title)
        if db_state:
            return db_state

    # 2. Window title / command text markers
    text = (title + " " + cmd).lower()
    if any(k in text for k in ["error", "fail", "crash", "exit 1"]):
        return STATE_DEFS["error"]
    if any(k in text for k in ["waiting", "approval", "permission", "confirm", "[y/n]"]):
        return STATE_DEFS["approval"]
    if any(k in text for k in ["question", "ask", "prompt?"]):
        return STATE_DEFS["question"]
    if any(k in text for k in ["search", "grep", "find", "query", "fetch"]):
        return STATE_DEFS["searching"]
    if any(k in text for k in ["rate limit", "429"]):
        return STATE_DEFS["ratelimit"]
    if any(k in text for k in ["done", "finish", "complete", "success"]):
        return STATE_DEFS["finished"]

    # 3. Real-time CPU & active child process activity
    if inst_cpu >= 8.0 or has_children:
        return STATE_DEFS["working"]
    elif inst_cpu >= 1.5:
        return STATE_DEFS["thinking"]
    else:
        return STATE_DEFS["idle"]

my_pid = str(os.getpid())
my_ppid = str(os.getppid())

try:
    out = subprocess.check_output(["ps", "-eo", "pid,%cpu,%mem,etime,args"], text=True)
    lines = out.strip().splitlines()[1:]
except Exception:
    lines = []

active_agents = []
installed_harnesses = []
new_cache = {}

for target in targets:
    bin_name, bin_path = check_bin(target["bins"])
    is_installed = bin_path is not None

    regex = re.compile(target["pattern"], re.IGNORECASE)
    matched = []
    for line in lines:
        parts = line.strip().split(None, 4)
        if len(parts) >= 5:
            pid_s, cpu, mem, etime, cmd = parts
            if pid_s in (my_pid, my_ppid):
                continue
            if "agent_monitor" in cmd or "ps -eo" in cmd:
                continue
            if regex.search(cmd):
                try:
                    c = float(cpu)
                    m = float(mem)
                except ValueError:
                    c, m = 0.0, 0.0
                matched.append({
                    "pid": int(pid_s),
                    "cpu": c,
                    "mem": m,
                    "etime": etime,
                    "cmd": cmd
                })

    is_running = len(matched) > 0

    if is_installed:
        installed_harnesses.append({
            "id": target["id"],
            "name": target["name"],
            "icon": target["icon"],
            "color": target["color"],
            "bin": bin_name,
            "path": bin_path,
            "running": is_running,
            "count": len(matched)
        })

    if not is_installed and not is_running:
        continue

    instances = []
    seen_windows = set()
    total_inst_cpu = 0.0
    total_mem = sum(p["mem"] for p in matched)

    for p in matched:
        pid = p["pid"]
        win = find_window(pid)
        cmd_str = p["cmd"].strip()
        activity = cmd_str.split("/")[-1] if "/" in cmd_str else cmd_str
        if len(activity) > 40:
            activity = activity[:37] + "..."

        addr = win.get("address", "") if win else ""
        title = win.get("title", "") if win else ""
        ws_id = str(win.get("workspace", {}).get("id", "")) if win else ""

        if addr:
            if addr in seen_windows:
                continue
            seen_windows.add(addr)

        # Real-time instantaneous CPU calculation
        tree_ticks = get_tree_ticks(pid)
        children = get_descendants(pid)
        has_children = len(children) > 0

        pid_key = str(pid)
        if pid_key in tick_cache:
            prev = tick_cache[pid_key]
            dt = max(0.001, now_s - prev.get("time", now_s))
            dticks = max(0, tree_ticks - prev.get("ticks", tree_ticks))
            inst_cpu = (dticks / 100.0) / dt * 100.0
        else:
            # First time seen: fast 35ms sample to determine if actually doing work
            t1 = tree_ticks
            time.sleep(0.035)
            tree_ticks = get_tree_ticks(pid)
            inst_cpu = max(0.0, ((tree_ticks - t1) / 100.0) / 0.035 * 100.0)

        new_cache[pid_key] = {"ticks": tree_ticks, "time": now_s}
        total_inst_cpu += inst_cpu

        mochi = get_mochi_state(target["id"], pid, inst_cpu, has_children, cmd_str, title, True)

        instances.append({
            "pid": str(pid),
            "cpu": "{:.1f}".format(inst_cpu),
            "mem": "{:.1f}".format(p["mem"]),
            "etime": p["etime"],
            "activity": activity,
            "window_address": addr,
            "window_title": title if title else "Terminal #" + str(len(instances) + 1),
            "workspace_id": ws_id,
            "mochi": mochi
        })

    # Sort instances: prioritize active state (Working/Thinking/Approval > Idle), then windowed, then workspace
    instances.sort(
        key=lambda x: (
            -STATE_PRIORITY.get(x["mochi"]["state"], 0),
            0 if x["window_address"] else 1,
            x["workspace_id"]
        )
    )

    top_instance = instances[0] if instances else None
    top_mochi = top_instance["mochi"] if top_instance else get_mochi_state(target["id"], 0, total_inst_cpu, False, "", "", is_running)

    windowed = [i for i in instances if i["window_address"]]

    active_agents.append({
        "id": target["id"],
        "name": target["name"],
        "icon": target["icon"],
        "color": target["color"],
        "installed": is_installed,
        "bin": bin_name if bin_name else target["bins"][0],
        "running": is_running,
        "count": len(matched),
        "terminal_count": len(windowed),
        "pid": top_instance["pid"] if top_instance else "-",
        "cpu": "{:.1f}".format(total_inst_cpu),
        "mem": "{:.1f}".format(total_mem),
        "etime": top_instance["etime"] if top_instance else "-",
        "activity": top_instance["activity"] if top_instance else ("Idle" if is_installed else "Not Installed"),
        "window_address": top_instance["window_address"] if top_instance else "",
        "window_title": top_instance["window_title"] if top_instance else "",
        "workspace_id": top_instance["workspace_id"] if top_instance else "",
        "instances": windowed if windowed else instances,
        "mochi": top_mochi
    })

# Save updated cache for next cycle
try:
    with open(CACHE_FILE, "w") as f:
        json.dump(new_cache, f)
except Exception:
    pass

output = {
    "agents": active_agents,
    "installed_harnesses": installed_harnesses
}

print(json.dumps(output))
