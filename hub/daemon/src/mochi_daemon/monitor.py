from __future__ import annotations

import json
import os
import re
import shutil
import sqlite3
import subprocess
import time
from typing import Any

from mochi_daemon.models import AgentInfo, MochiState, SystemState

# Default supported agent harnesses adapted from agent_monitor.py
DEFAULT_TARGETS: list[dict[str, Any]] = [
    {
        "id": "opencode",
        "name": "OpenCode",
        "icon": "terminal",
        "color": "#4ADE80",
        "bins": ["opencode"],
        "pattern": r"(^|[\s/])opencode(\s|$)",
    },
    {
        "id": "claude",
        "name": "Claude Code",
        "icon": "smart_toy",
        "color": "#D97757",
        "bins": ["claude", "claude-code"],
        "pattern": r"(^|[\s/])(claude|claude-code)(\s|$)",
    },
    {
        "id": "antigravity",
        "name": "Antigravity",
        "icon": "rocket_launch",
        "color": "#E879F9",
        "bins": ["antigravity", "agy"],
        "pattern": r"(^|[\s/])(antigravity|agy)(\s|$)",
    },
    {
        "id": "codex",
        "name": "Codex",
        "icon": "code",
        "color": "#2DD4BF",
        "bins": ["codex"],
        "pattern": r"(^|[\s/])codex(\s|$)",
    },
    {
        "id": "aider",
        "name": "Aider",
        "icon": "psychology",
        "color": "#38BDF8",
        "bins": ["aider"],
        "pattern": r"(^|[\s/])aider(\s|$)",
    },
    {
        "id": "cursor",
        "name": "Cursor",
        "icon": "edit_square",
        "color": "#818CF8",
        "bins": ["cursor", "cursor-agent"],
        "pattern": r"(^|[\s/])cursor(-agent)?(\s|$)",
    },
    {
        "id": "windsurf",
        "name": "Windsurf",
        "icon": "surfing",
        "color": "#06B6D4",
        "bins": ["windsurf"],
        "pattern": r"(^|[\s/])windsurf(\s|$)",
    },
    {
        "id": "goose",
        "name": "Goose AI",
        "icon": "flutter",
        "color": "#F59E0B",
        "bins": ["goose", "goose-ai"],
        "pattern": r"(^|[\s/])goose(-ai)?(\s|$)",
    },
    {
        "id": "plandex",
        "name": "Plandex",
        "icon": "alt_route",
        "color": "#EC4899",
        "bins": ["plandex"],
        "pattern": r"(^|[\s/])plandex(\s|$)",
    },
    {
        "id": "cline",
        "name": "Cline",
        "icon": "terminal",
        "color": "#10B981",
        "bins": ["cline"],
        "pattern": r"(^|[\s/])cline(\s|$)",
    },
    {
        "id": "continue",
        "name": "Continue",
        "icon": "fast_forward",
        "color": "#6366F1",
        "bins": ["continue"],
        "pattern": r"(^|[\s/])continue(\s|$)",
    },
]

STATE_PRIORITY: dict[MochiState, int] = {
    MochiState.APPROVAL: 9,
    MochiState.QUESTION: 8,
    MochiState.WORKING: 7,
    MochiState.SEARCHING: 6,
    MochiState.THINKING: 5,
    MochiState.DONE: 4,
    MochiState.IDLE: 2,
    MochiState.SLEEPING: 1,
}

EXTRA_PATHS: list[str] = [
    os.path.expanduser("~/.local/bin"),
    os.path.expanduser("~/.cargo/bin"),
    os.path.expanduser("~/.bun/bin"),
    os.path.expanduser("~/.npm-global/bin"),
    "/usr/local/bin",
    "/usr/bin",
]


class AgentMonitorService:
    def __init__(
        self,
        targets: list[dict[str, Any]] | None = None,
        db_path: str | None = None,
        cache_file: str | None = "/tmp/caelestia_agent_ticks.json",
    ):
        self.targets = targets or DEFAULT_TARGETS
        self.db_path = db_path or os.path.expanduser("~/.local/share/opencode/opencode.db")
        self.cache_file = cache_file
        self._tick_cache: dict[str, dict[str, float]] = {}

        if self.cache_file and os.path.exists(self.cache_file):
            try:
                with open(self.cache_file, "r") as f:
                    self._tick_cache = json.load(f)
            except Exception:
                self._tick_cache = {}

    def _get_search_path(self) -> str:
        current_path = os.environ.get("PATH", "")
        valid_extras = [p for p in EXTRA_PATHS if os.path.isdir(p)]
        return ":".join(valid_extras + [current_path])

    def _check_bin(self, bins: list[str], search_path: str) -> tuple[str | None, str | None]:
        for b in bins:
            p = shutil.which(b, path=search_path)
            if p:
                return b, p
        return None, None

    def _get_hypr_clients(self) -> list[dict[str, Any]]:
        try:
            out = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
            return json.loads(out)
        except Exception:
            return []

    def _get_parent_map(self) -> dict[int, int]:
        parent_map: dict[int, int] = {}
        try:
            ps_tree = subprocess.check_output(["ps", "-eo", "pid,ppid"], text=True).splitlines()[1:]
            for line in ps_tree:
                parts = line.strip().split()
                if len(parts) == 2:
                    parent_map[int(parts[0])] = int(parts[1])
        except Exception:
            pass
        return parent_map

    def _get_descendants(self, pid: int, parent_map: dict[int, int]) -> list[int]:
        desc: list[int] = []
        visited: set[int] = {pid}
        stack = [pid]
        while stack:
            curr = stack.pop()
            for child, parent in parent_map.items():
                if parent == curr and child not in visited:
                    visited.add(child)
                    desc.append(child)
                    stack.append(child)
        return desc

    def _find_window(
        self, pid: int, client_by_pid: dict[int, Any], parent_map: dict[int, int]
    ) -> dict[str, Any] | None:
        curr = pid
        visited = set()
        for _ in range(6):
            if curr in client_by_pid:
                return client_by_pid[curr]
            if curr in visited or curr not in parent_map:
                break
            visited.add(curr)
            curr = parent_map[curr]
        return None

    def _get_pid_ticks(self, pid: int) -> int:
        try:
            with open(f"/proc/{pid}/stat", "r") as f:
                fields = f.read().split()
                return int(fields[13]) + int(fields[14])
        except Exception:
            return 0

    def _get_tree_ticks(self, pid: int, parent_map: dict[int, int]) -> int:
        ticks = self._get_pid_ticks(pid)
        for c in self._get_descendants(pid, parent_map):
            ticks += self._get_pid_ticks(c)
        return ticks

    def _get_process_lines(self) -> list[str]:
        try:
            out = subprocess.check_output(["ps", "-eo", "pid,%cpu,%mem,etime,args"], text=True)
            return out.strip().splitlines()[1:]
        except Exception:
            return []

    def inspect_opencode_db(self, pid: int, title: str) -> MochiState | None:
        if not os.path.exists(self.db_path):
            return None
        conn = None
        try:
            conn = sqlite3.connect(f"file:{self.db_path}?mode=ro", uri=True)
            c = conn.cursor()

            sid = None
            if title and title.startswith("OC | "):
                stitle = title[5:].strip()
                c.execute("SELECT id FROM session_v2 WHERE title = ? ORDER BY time_updated DESC LIMIT 1", (stitle,))
                row = c.fetchone()
                if not row and len(stitle) > 10:
                    c.execute(
                        "SELECT id FROM session_v2 WHERE title LIKE ? ORDER BY time_updated DESC LIMIT 1",
                        (stitle[:20] + "%",),
                    )
                    row = c.fetchone()
                if row:
                    sid = row[0]

            if not sid and pid:
                try:
                    cwd = os.readlink(f"/proc/{pid}/cwd")
                    c.execute(
                        "SELECT id FROM session_v2 WHERE directory = ? ORDER BY time_updated DESC LIMIT 1",
                        (cwd,),
                    )
                    row = c.fetchone()
                    if row:
                        sid = row[0]
                except Exception:
                    pass

            if not sid:
                return MochiState.IDLE

            c.execute(
                "SELECT data FROM session_message WHERE session_id = ? ORDER BY time_created DESC LIMIT 1",
                (sid,),
            )
            row = c.fetchone()
            if not row:
                return MochiState.IDLE

            data = json.loads(row[0])
            now_ms = time.time() * 1000

            if "outcome" in data:
                t_done = data.get("time", {}).get("created", 0)
                if now_ms - t_done < 15000:
                    return MochiState.DONE
                return MochiState.IDLE

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
                            return MochiState.QUESTION
                        if tool_name in ("grep", "glob", "websearch", "webfetch"):
                            return MochiState.SEARCHING
                        return MochiState.WORKING
                elif itype == "reasoning":
                    return MochiState.THINKING

            if data.get("agent") and not data.get("finish"):
                return MochiState.THINKING

            return MochiState.IDLE
        except Exception:
            return None
        finally:
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass

    def _determine_instance_state(
        self,
        target_id: str,
        pid: int,
        inst_cpu: float,
        has_children: bool,
        cmd: str,
        title: str,
        is_running: bool,
    ) -> MochiState:
        if not is_running:
            return MochiState.SLEEPING

        # 1. Native OpenCode DB inspection
        if target_id == "opencode":
            db_state = self.inspect_opencode_db(pid, title)
            if db_state:
                return db_state

        # 2. Window title / command text markers
        text = f"{title} {cmd}".lower()
        if re.search(r"(?:^|[\s/_-])(waiting|approval|permission|confirm|\[y/n\])", text):
            return MochiState.APPROVAL
        if re.search(r"(?:^|[\s/_-])(question|ask|prompt\?)", text):
            return MochiState.QUESTION
        if re.search(r"(?:^|[\s/_-])(search|grep|find|query|fetch)", text):
            return MochiState.SEARCHING
        if re.search(r"(?:^|[\s/_-])(done|finish|complete|success)", text):
            return MochiState.DONE


        # 3. CPU tick delta & child process heuristic
        if inst_cpu >= 8.0 or has_children:
            return MochiState.WORKING
        elif inst_cpu >= 1.5:
            return MochiState.THINKING
        return MochiState.IDLE

    def get_system_state(self) -> SystemState:
        now_s = time.time()
        search_path = self._get_search_path()
        hypr_clients = self._get_hypr_clients()
        client_by_pid = {c.get("pid"): c for c in hypr_clients if c.get("pid")}
        parent_map = self._get_parent_map()
        lines = self._get_process_lines()

        my_pid = str(os.getpid())
        my_ppid = str(os.getppid())

        agents: list[AgentInfo] = []
        new_cache: dict[str, dict[str, float]] = {}

        for target in self.targets:
            bin_name, bin_path = self._check_bin(target["bins"], search_path)
            is_installed = bin_path is not None

            regex = re.compile(target["pattern"], re.IGNORECASE)
            matched: list[dict[str, Any]] = []

            for line in lines:
                parts = line.strip().split(None, 4)
                if len(parts) >= 5:
                    pid_s, cpu, mem, etime, cmd = parts
                    if pid_s in (my_pid, my_ppid):
                        continue
                    if "agent_monitor" in cmd or "mochi_daemon" in cmd or "ps -eo" in cmd:
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
                            "cmd": cmd,
                        })

            is_running = len(matched) > 0

            # ponytail: skip non-installed and non-running targets to reduce payload size
            if not is_installed and not is_running:
                continue

            instances: list[dict[str, Any]] = []
            seen_windows: set[str] = set()
            total_inst_cpu = 0.0
            total_mem = sum(p["mem"] for p in matched)

            for p in matched:
                pid = p["pid"]
                win = self._find_window(pid, client_by_pid, parent_map)
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

                tree_ticks = self._get_tree_ticks(pid, parent_map)
                children = self._get_descendants(pid, parent_map)
                has_children = len(children) > 0

                pid_key = str(pid)
                if pid_key in self._tick_cache:
                    prev = self._tick_cache[pid_key]
                    dt = max(0.001, now_s - prev.get("time", now_s))
                    dticks = max(0, tree_ticks - prev.get("ticks", tree_ticks))
                    inst_cpu = (dticks / 100.0) / dt * 100.0
                else:
                    t1 = tree_ticks
                    time.sleep(0.035)
                    tree_ticks = self._get_tree_ticks(pid, parent_map)
                    inst_cpu = max(0.0, ((tree_ticks - t1) / 100.0) / 0.035 * 100.0)

                new_cache[pid_key] = {"ticks": tree_ticks, "time": now_s}
                total_inst_cpu += inst_cpu

                mochi = self._determine_instance_state(
                    target["id"], pid, inst_cpu, has_children, cmd_str, title, True
                )

                instances.append({
                    "pid": str(pid),
                    "cpu": round(inst_cpu, 1),
                    "mem": round(p["mem"], 1),
                    "etime": p["etime"],
                    "activity": activity,
                    "window_address": addr,
                    "window_title": title or f"Terminal #{len(instances) + 1}",
                    "workspace_id": ws_id,
                    "mochi_state": mochi.value,
                })

            instances.sort(
                key=lambda x: (
                    -STATE_PRIORITY.get(MochiState(x["mochi_state"]), 0),
                    0 if x["window_address"] else 1,
                    x["workspace_id"],
                )
            )

            top_instance = instances[0] if instances else None
            top_state = (
                MochiState(top_instance["mochi_state"])
                if top_instance
                else (MochiState.IDLE if is_installed else MochiState.SLEEPING)
            )

            windowed = [i for i in instances if i["window_address"]]

            agent_info = AgentInfo(
                name=target["name"],
                command=top_instance["activity"] if top_instance else (bin_name or target["id"]),
                pid=int(top_instance["pid"]) if top_instance else None,
                status=top_state.value,
                cpu=round(total_inst_cpu, 1),
                memory=round(total_mem, 1),
                details={
                    "id": target["id"],
                    "icon": target["icon"],
                    "color": target["color"],
                    "installed": is_installed,
                    "bin": bin_name if bin_name else target["bins"][0],
                    "running": is_running,
                    "count": len(matched),
                    "terminal_count": len(windowed),
                    "window_address": top_instance["window_address"] if top_instance else "",
                    "window_title": top_instance["window_title"] if top_instance else "",
                    "workspace_id": top_instance["workspace_id"] if top_instance else "",
                    "instances": windowed if windowed else instances,
                },
            )
            agents.append(agent_info)

        self._tick_cache.update(new_cache)
        if self.cache_file:
            try:
                with open(self.cache_file, "w") as f:
                    json.dump(self._tick_cache, f)
            except Exception:
                pass

        # Identify active agent & overall mochi state
        running_agents = [a for a in agents if a.details.get("running")]
        if running_agents:
            active_agent = max(
                running_agents,
                key=lambda a: (STATE_PRIORITY.get(MochiState(a.status), 0), a.cpu),
            )
            overall_state = MochiState(active_agent.status)
        else:
            active_agent = None
            overall_state = MochiState.SLEEPING

        return SystemState(
            timestamp=now_s,
            agents=agents,
            active_agent=active_agent,
            mochi_state=overall_state,
        )
