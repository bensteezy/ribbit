#!/usr/bin/env python3
"""Forward provider lifecycle events to Ribbit without altering the agent run."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import urllib.request

BRIDGE_URL = "http://127.0.0.1:9848/v1/events"


def _terminal_tty() -> str | None:
    tty = os.environ.get("TTY")
    if tty:
        return tty
    for stream in (sys.stdout, sys.stderr):
        try:
            return os.ttyname(stream.fileno())
        except OSError:
            pass
    try:
        terminal_name = subprocess.check_output(
            ["/bin/ps", "-o", "tty=", "-p", str(os.getppid())],
            text=True,
            timeout=0.25,
        ).strip()
        if terminal_name and terminal_name not in {"??", "?"}:
            return (
                terminal_name
                if terminal_name.startswith("/dev/")
                else f"/dev/{terminal_name}"
            )
    except Exception:
        pass
    return None


def _tmux_focus() -> dict:
    tmux_environment = os.environ.get("TMUX", "")
    tmux_path = shutil.which("tmux")
    if not tmux_environment or not tmux_path:
        return {}
    socket_path = tmux_environment.split(",", 1)[0]
    try:
        target = subprocess.check_output(
            [
                tmux_path,
                "-S",
                socket_path,
                "display-message",
                "-p",
                "#{session_name}:#{window_index}.#{pane_index}",
            ],
            text=True,
            timeout=0.25,
        ).strip()
        session_name = target.split(":", 1)[0]
        clients = subprocess.check_output(
            [
                tmux_path,
                "-S",
                socket_path,
                "list-clients",
                "-F",
                "#{session_name}\t#{client_tty}",
            ],
            text=True,
            timeout=0.25,
        )
        client_tty = next(
            (
                line.split("\t", 1)[1]
                for line in clients.splitlines()
                if line.split("\t", 1)[0] == session_name and "\t" in line
            ),
            None,
        )
        return {
            "tmuxTarget": target or None,
            "tmuxSocketPath": socket_path or None,
            "tty": client_tty,
        }
    except Exception:
        return {}


def _application_name(term_program: str) -> str:
    return {
        "Apple_Terminal": "Terminal",
        "iTerm.app": "iTerm2",
        "vscode": "Code",
        "cursor": "Cursor",
        "WezTerm": "WezTerm",
        "ghostty": "Ghostty",
        "WarpTerminal": "Warp",
    }.get(term_program, term_program or "Terminal")


def focus_target(provider: str, cwd: str) -> dict:
    process_id = os.getppid()
    ribbit_terminal_id = os.environ.get("RIBBIT_TERMINAL_ID")
    if not ribbit_terminal_id and os.environ.get("TMUX"):
        try:
            session_name = subprocess.check_output(
                ["tmux", "display-message", "-p", "#S"],
                text=True,
                timeout=0.25,
            ).strip()
            candidate = session_name[-36:]
            if session_name.startswith("ribbit-") and len(candidate) == 36:
                ribbit_terminal_id = candidate
        except Exception:
            pass
    if ribbit_terminal_id:
        return {
            "surface": "ribbit",
            "applicationName": "ribbit",
            "terminalSessionID": ribbit_terminal_id,
            "workingDirectory": cwd,
            "processID": process_id,
        }

    term_program = os.environ.get("TERM_PROGRAM", "")
    tty = _terminal_tty()
    tmux = _tmux_focus()
    focus_tty = tmux.get("tty") or tty
    shared = {
        "tty": focus_tty,
        "workingDirectory": cwd,
        "processID": process_id,
        "tmuxTarget": tmux.get("tmuxTarget"),
        "tmuxSocketPath": tmux.get("tmuxSocketPath"),
    }
    if term_program == "iTerm.app":
        return {
            "surface": "iTerm",
            "applicationName": "iTerm2",
            "iTermSessionID": os.environ.get("ITERM_SESSION_ID"),
            "terminalSessionID": os.environ.get("TERM_SESSION_ID"),
            **shared,
        }
    if term_program == "Apple_Terminal":
        return {
            "surface": "terminal",
            "applicationName": "Terminal",
            "terminalSessionID": os.environ.get("TERM_SESSION_ID"),
            **shared,
        }
    if provider == "cursor":
        return {
            "surface": "cursor",
            "applicationName": "Cursor",
            **shared,
        }
    if provider == "codex" and not term_program and not focus_tty:
        return {
            "surface": "codex",
            "applicationName": "ChatGPT",
            **shared,
        }
    return {
        "surface": "application",
        "applicationName": _application_name(term_program),
        "terminalSessionID": os.environ.get("TERM_SESSION_ID"),
        **shared,
    }


def normalized_event(raw: dict, provider: str) -> dict:
    event_key = str(raw.get("hook_event_name", "")).lower()
    notification = raw.get("notification_type", "")
    roots = raw.get("workspace_roots") or []
    cwd = raw.get("cwd") or (roots[0] if roots else None) or os.getcwd()
    project_root = os.environ.get("RIBBIT_PROJECT_ROOT") or cwd
    project = os.path.basename(project_root.rstrip("/")) or "local"
    session_id = (
        raw.get("session_id")
        or raw.get("conversation_id")
        or raw.get("thread_id")
        or project
    )
    tool_name = raw.get("tool_name") or raw.get("tool") or "tool"
    detail = raw.get("message") or raw.get("title") or ""

    payload = {
        "id": f"{provider}:{session_id}",
        "providerSessionID": session_id,
        "agent": provider,
        "title": f"{provider} session",
        "project": project,
        "activity": "agent activity",
        "state": "running",
        "focusTarget": focus_target(provider, cwd),
    }

    if event_key == "permissionrequest" or notification == "permission_prompt":
        payload.update(
            activity="permission requested",
            state="attention",
            attentionKind="permission",
            attentionDetail=detail or f"{tool_name} requires approval.",
        )
    elif notification in {"idle_prompt", "elicitation_dialog"}:
        payload.update(
            activity="waiting for your input",
            state="attention",
            attentionKind="question",
            attentionDetail=detail or "open the agent to answer its question.",
        )
    elif event_key == "sessionstart":
        payload.update(activity="ready for a prompt", state="paused")
    elif event_key in {"userpromptsubmit", "beforesubmitprompt", "subagentstart"}:
        payload.update(activity="working from your prompt", state="running")
    elif event_key in {"precompact", "postcompact"}:
        payload.update(activity="compacting context", state="running")
    elif event_key in {
        "pretooluse",
        "beforeshellexecution",
        "beforemcpexecution",
    }:
        payload.update(activity=f"using {tool_name}", state="running")
    elif event_key in {
        "posttooluse",
        "posttoolusefailure",
        "aftershellexecution",
        "aftermcpexecution",
        "afterfileedit",
        "afteragentresponse",
        "afteragentthought",
    }:
        payload.update(activity="continuing after tool use", state="running")
    elif event_key in {"stop", "subagentstop"}:
        payload.update(activity="ready for another prompt", state="paused")
    elif event_key == "stopfailure":
        payload.update(
            activity=detail or "stopped with an error",
            state="paused",
        )
    elif event_key == "permissiondenied":
        payload.update(
            activity=detail or f"{tool_name} was denied",
            state="running",
        )
    elif event_key == "sessionend":
        payload.update(activity="session ended", state="completed")
    return payload


def main() -> int:
    provider = sys.argv[1] if len(sys.argv) > 1 else "codex"
    if provider not in {"codex", "claude", "cursor"}:
        return 0
    try:
        raw = json.load(sys.stdin)
        request = urllib.request.Request(
            BRIDGE_URL,
            data=json.dumps(normalized_event(raw, provider)).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=0.75):
            pass
    except Exception:
        # Observability must never interrupt the provider.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
