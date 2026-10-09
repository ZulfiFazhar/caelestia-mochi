from __future__ import annotations

import atexit
import asyncio
import logging
import os
import pty
import re
import select
import shlex
import signal
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Callable

if TYPE_CHECKING:
    from mochi_daemon.api import EventBroadcaster

logger = logging.getLogger(__name__)

APPROVAL_PATTERNS = [
    re.compile(r"\[[yY]/[nN]\]"),
    re.compile(r"\([yY]/[nN]\)"),
    re.compile(r"\[[nN]/[yY]\]"),
    re.compile(r"\bAllow\s*(?:\([aA]\))?", re.IGNORECASE),
    re.compile(r"\bApprove\??\b", re.IGNORECASE),
    re.compile(r"\bConfirm\??\b", re.IGNORECASE),
    re.compile(r"Do you want to (?:proceed|continue)\??", re.IGNORECASE),
    re.compile(r"\bPermission\s+required\b", re.IGNORECASE),
]

# ponytail: regex tail-scanning for approval prompts; switch to full ANSI terminal state machine emulator (pyte) if terminal cursor-rewriting masks prompt strings
ANSI_ESCAPE = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


def _kill_proc_group(pid: int, sig: int) -> None:
    try:
        os.killpg(pid, sig)
    except (ProcessLookupError, PermissionError):
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass


@dataclass
class _Session:
    session_id: str
    command: list[str]
    proc: subprocess.Popen
    master_fd: int | None
    created_at: float
    output: str = ""
    approval_cursor: int = 0
    is_active: bool = True
    reader_thread: threading.Thread | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)
    pending_approval: dict[str, Any] | None = None


class PtySessionManager:
    def __init__(
        self,
        broadcaster: Any | None = None,
        loop: asyncio.AbstractEventLoop | None = None,
        on_approval: Callable[[dict[str, Any]], Any] | None = None,
    ) -> None:
        self.broadcaster = broadcaster
        self.on_approval = on_approval
        self._sessions: dict[str, _Session] = {}
        self._approvals: dict[str, dict[str, Any]] = {}
        self._lock = threading.Lock()

        try:
            self.loop = loop or asyncio.get_running_loop()
        except RuntimeError:
            self.loop = loop

        atexit.register(self.terminate_all)

    def spawn_session(
        self,
        command: list[str] | str,
        env: dict[str, str] | None = None,
        cwd: str | None = None,
    ) -> str:
        cmd_list = shlex.split(command) if isinstance(command, str) else list(command)
        session_id = f"session-{uuid.uuid4().hex[:8]}"

        master_fd, slave_fd = pty.openpty()

        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        merged_env.setdefault("TERM", "xterm-256color")

        try:
            proc = subprocess.Popen(
                cmd_list,
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                start_new_session=True,
                env=merged_env,
                cwd=cwd,
                close_fds=True,
            )
        except Exception:
            try:
                os.close(master_fd)
            except OSError:
                pass
            try:
                os.close(slave_fd)
            except OSError:
                pass
            raise
        finally:
            try:
                os.close(slave_fd)
            except OSError:
                pass

        session = _Session(
            session_id=session_id,
            command=cmd_list,
            proc=proc,
            master_fd=master_fd,
            created_at=time.time(),
        )

        with self._lock:
            self._sessions[session_id] = session

        # ponytail: reader thread per active session; switch to selectors/asyncio loop when scaling >100 concurrent sessions
        t = threading.Thread(
            target=self._reader_loop,
            args=(session,),
            name=f"pty-reader-{session_id}",
            daemon=True,
        )
        session.reader_thread = t
        t.start()

        return session_id

    def send_input(self, session_id: str, data: str) -> None:
        with self._lock:
            session = self._sessions.get(session_id)
        if not session:
            raise KeyError(f"Session not found: {session_id}")

        with session.lock:
            fd = session.master_fd
            if fd is None:
                raise RuntimeError(f"Session {session_id} has no open file descriptor")
            payload = data.encode("utf-8")
            os.write(fd, payload)

    def get_output(self, session_id: str) -> str:
        with self._lock:
            session = self._sessions.get(session_id)
        if not session:
            raise KeyError(f"Session not found: {session_id}")
        with session.lock:
            return session.output

    def get_session(self, session_id: str) -> dict[str, Any] | None:
        with self._lock:
            session = self._sessions.get(session_id)
        if not session:
            return None
        with session.lock:
            return {
                "session_id": session.session_id,
                "command": list(session.command),
                "pid": session.proc.pid,
                "running": session.proc.poll() is None,
                "returncode": session.proc.returncode,
                "created_at": session.created_at,
                "has_pending_approval": session.pending_approval is not None,
                "pending_approval": dict(session.pending_approval)
                if session.pending_approval
                else None,
            }

    def list_sessions(self) -> list[dict[str, Any]]:
        with self._lock:
            session_ids = list(self._sessions.keys())
        res = []
        for sid in session_ids:
            s = self.get_session(sid)
            if s:
                res.append(s)
        return res

    def get_approval(self, approval_id: str) -> dict[str, Any] | None:
        with self._lock:
            appr = self._approvals.get(approval_id)
            return dict(appr) if appr else None

    def list_pending_approvals(self) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(a) for a in self._approvals.values() if not a.get("resolved")]

    def submit_approval(
        self,
        approval_id: str,
        approved: bool = True,
        response_text: str | None = None,
    ) -> bool:
        with self._lock:
            approval = self._approvals.get(approval_id)
            if not approval or approval.get("resolved"):
                return False
            approval["resolved"] = True
            approval["approved"] = approved
            session_id = approval["session_id"]
            prompt = approval.get("prompt", "")
            matched_text = approval.get("matched_text", "")

        with self._lock:
            session = self._sessions.get(session_id)
        if not session:
            return False

        with session.lock:
            session.pending_approval = None
            session.approval_cursor = len(session.output)

        if response_text is not None:
            to_send = response_text
        else:
            combined = f"{prompt} {matched_text}".lower()
            if approved:
                if "(a)" in combined or "[a]" in combined:
                    to_send = "a\n"
                else:
                    to_send = "y\n"
            else:
                to_send = "n\n"

        if not to_send.endswith("\n"):
            to_send += "\n"

        try:
            self.send_input(session_id, to_send)
        except Exception as e:
            logger.warning(f"Failed to send approval response to session {session_id}: {e}")
            return False

        return True

    def terminate_session(self, session_id: str, force: bool = False) -> None:
        with self._lock:
            session = self._sessions.get(session_id)
        if not session:
            return

        session.is_active = False
        pid = session.proc.pid
        sig = signal.SIGKILL if force else signal.SIGTERM

        if session.proc.poll() is None:
            _kill_proc_group(pid, sig)
            try:
                session.proc.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                _kill_proc_group(pid, signal.SIGKILL)
                try:
                    session.proc.wait(timeout=0.5)
                except subprocess.TimeoutExpired:
                    pass

        if session.reader_thread and session.reader_thread.is_alive():
            session.reader_thread.join(timeout=0.5)

        with session.lock:
            if session.master_fd is not None:
                try:
                    os.close(session.master_fd)
                except OSError:
                    pass
                session.master_fd = None

            if session.pending_approval:
                session.pending_approval["resolved"] = True
                session.pending_approval = None

    def terminate_all(self) -> None:
        with self._lock:
            session_ids = list(self._sessions.keys())
        for sid in session_ids:
            self.terminate_session(sid, force=True)

    def close(self) -> None:
        self.terminate_all()

    def __enter__(self) -> PtySessionManager:
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.terminate_all()

    def __del__(self) -> None:
        try:
            self.terminate_all()
        except Exception:
            pass

    def _reader_loop(self, session: _Session) -> None:
        fd = session.master_fd
        while session.is_active and fd is not None:
            try:
                r, _, _ = select.select([fd], [], [], 0.05)
                if not r:
                    if session.proc.poll() is not None:
                        # Process exited; drain final output
                        try:
                            chunk = os.read(fd, 4096)
                            if chunk:
                                text = chunk.decode("utf-8", errors="replace")
                                with session.lock:
                                    session.output += text
                                self._check_approval(session)
                        except OSError:
                            pass
                        break
                    continue

                chunk = os.read(fd, 4096)
                if not chunk:
                    break

                text = chunk.decode("utf-8", errors="replace")
                with session.lock:
                    session.output += text
                self._check_approval(session)
            except (OSError, select.error):
                break
            except Exception as e:
                logger.debug(f"Exception in PTY reader for session {session.session_id}: {e}")
                break

        with session.lock:
            if session.master_fd is not None:
                try:
                    os.close(session.master_fd)
                except OSError:
                    pass
                session.master_fd = None

    def _check_approval(self, session: _Session) -> None:
        with session.lock:
            if session.pending_approval is not None:
                return
            text_to_check = session.output[session.approval_cursor :]

        if not text_to_check:
            return

        clean_text = ANSI_ESCAPE.sub("", text_to_check)
        for pattern in APPROVAL_PATTERNS:
            match = pattern.search(clean_text)
            if match:
                approval_id = f"appr-{uuid.uuid4().hex[:8]}"
                approval_info = {
                    "approval_id": approval_id,
                    "session_id": session.session_id,
                    "prompt": match.group(0),
                    "matched_text": clean_text.strip(),
                    "timestamp": time.time(),
                    "resolved": False,
                }
                with session.lock:
                    session.pending_approval = approval_info
                with self._lock:
                    self._approvals[approval_id] = approval_info
                self._notify_approval(approval_info)
                break

    def _notify_approval(self, approval_info: dict[str, Any]) -> None:
        if self.on_approval:
            try:
                self.on_approval(approval_info)
            except Exception as e:
                logger.warning(f"Error calling on_approval callback: {e}")

        if self.broadcaster:
            try:
                loop = self.loop
                if loop is None or loop.is_closed():
                    try:
                        loop = asyncio.get_running_loop()
                    except RuntimeError:
                        loop = None

                if loop is not None and loop.is_running():
                    asyncio.run_coroutine_threadsafe(
                        self.broadcaster.broadcast_approval_request(approval_info),
                        loop,
                    )
                else:
                    try:
                        cur_loop = asyncio.get_event_loop()
                        if cur_loop.is_running():
                            asyncio.run_coroutine_threadsafe(
                                self.broadcaster.broadcast_approval_request(approval_info),
                                cur_loop,
                            )
                        else:
                            cur_loop.run_until_complete(
                                self.broadcaster.broadcast_approval_request(approval_info)
                            )
                    except Exception:
                        asyncio.run(
                            self.broadcaster.broadcast_approval_request(approval_info)
                        )
            except Exception as e:
                logger.warning(f"Error broadcasting approval request: {e}")
