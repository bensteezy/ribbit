#!/usr/bin/env python3
"""Forward provider lifecycle events to Ribbit without altering the agent run."""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import urllib.request
import uuid

BRIDGE_URL = "http://127.0.0.1:9848/v1/events"
SHELL_TOOL_NAMES = {"bash", "exec_command", "shell", "shellcommand"}
APPROVAL_TIMEOUT_SECONDS = 300


def _clean_text(value: object, limit: int = 600) -> str:
    text = " ".join(str(value or "").split())
    return text if len(text) <= limit else f"{text[: limit - 1]}…"


def _tool_summary(tool_name: str, tool_input: dict) -> str:
    for key in ("command", "cmd"):
        if tool_input.get(key):
            return _clean_text(tool_input[key])
    for key in ("file_path", "path", "notebook_path", "url"):
        if tool_input.get(key):
            return _clean_text(tool_input[key])
    for key in ("query", "pattern", "prompt", "description"):
        if tool_input.get(key):
            return _clean_text(tool_input[key])
    if tool_input:
        return _clean_text(json.dumps(tool_input, sort_keys=True))
    return f"Run {tool_name}"


def _latest_assistant_text(transcript_path: object) -> str | None:
    if not isinstance(transcript_path, str) or not transcript_path:
        return None
    try:
        with open(transcript_path, "rb") as transcript:
            transcript.seek(0, os.SEEK_END)
            size = transcript.tell()
            transcript.seek(max(0, size - 262_144))
            content = transcript.read().decode("utf-8", errors="ignore")
        for line in reversed(content.splitlines()):
            record = json.loads(line)
            if record.get("type") != "assistant":
                continue
            message = record.get("message") or {}
            blocks = message.get("content")
            if isinstance(blocks, str):
                return _clean_text(blocks)
            if isinstance(blocks, list):
                text = " ".join(
                    str(block.get("text", ""))
                    for block in blocks
                    if isinstance(block, dict) and block.get("type") == "text"
                )
                if text.strip():
                    return _clean_text(text)
    except Exception:
        pass
    return None


def _installed_cron(command: str) -> tuple[str, str] | None:
    """Return the schedule and command from a shell command that installs crontab."""
    if not re.search(r"(?:^|[/\s])crontab(?:\s|$)", command):
        return None
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None
    cron_field = re.compile(r"^[0-9A-Za-z*/?,#LW-]+$")
    for token in reversed(tokens):
        for line in reversed(token.splitlines()):
            fields = line.strip().split(maxsplit=5)
            if (
                len(fields) == 6
                and all(cron_field.fullmatch(field) for field in fields[:5])
            ):
                return " ".join(fields[:5]), fields[5]
    return None


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
    tool_input = raw.get("tool_input") or {}
    tool_response = raw.get("tool_response") or {}
    detail = raw.get("message") or raw.get("title") or ""
    summary = _tool_summary(str(tool_name), tool_input)

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
        if event_key == "permissionrequest" and provider == "claude":
            approval_id = str(uuid.uuid4())
            payload.update(
                approvalID=approval_id,
                approvalToolName=str(tool_name),
                approvalSummary=summary,
                attentionDetail=summary,
                conversationID=f"approval:{approval_id}",
                conversationRole="status",
                conversationText=f"Approval requested · {tool_name}: {summary}",
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
        prompt = raw.get("prompt") or raw.get("user_prompt")
        if event_key != "subagentstart" and prompt:
            payload.update(
                conversationID=str(uuid.uuid4()),
                conversationRole="user",
                conversationText=_clean_text(prompt),
            )
    elif event_key in {"precompact", "postcompact"}:
        payload.update(activity="compacting context", state="running")
    elif event_key in {
        "pretooluse",
        "beforeshellexecution",
        "beforemcpexecution",
    }:
        payload.update(activity=f"using {tool_name}", state="running")
        payload.update(
            conversationID=str(uuid.uuid4()),
            conversationRole="tool",
            conversationText=f"{tool_name} · {summary}",
        )
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
        assistant_text = (
            raw.get("last_assistant_message")
            or raw.get("response")
            or (
                _latest_assistant_text(raw.get("transcript_path"))
                if provider == "claude" and event_key == "stop"
                else None
            )
        )
        if assistant_text:
            payload.update(
                conversationID=str(uuid.uuid4()),
                conversationRole="assistant",
                conversationText=_clean_text(assistant_text),
            )
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

    if event_key == "userpromptsubmit":
        payload.update(
            canvasAction="remove",
            canvasActivityKind="subagent",
        )
    elif event_key == "pretooluse" and tool_name in {"Agent", "Task"}:
        payload.update(
            canvasAction="start",
            canvasActivityID=raw.get("tool_use_id") or f"subagent:{session_id}",
            canvasActivityKind="subagent",
            canvasActivityType=tool_input.get("subagent_type"),
            canvasTask=tool_input.get("description") or tool_input.get("prompt") or "",
        )
    elif event_key == "posttooluse" and tool_name in {"Agent", "Task"}:
        is_async = (
            tool_response.get("status") == "async_launched"
            or tool_response.get("isAsync") is True
        )
        if not is_async:
            payload.update(
                canvasAction="finish",
                canvasActivityID=raw.get("tool_use_id") or f"subagent:{session_id}",
                canvasActivityKind="subagent",
                canvasDurationMilliseconds=tool_response.get("totalDurationMs"),
                canvasTokens=tool_response.get("totalTokens"),
                canvasToolUses=tool_response.get("totalToolUseCount"),
            )
    elif event_key == "subagentstop":
        payload.update(
            canvasAction="finishOne",
            canvasActivityKind="subagent",
        )
    elif event_key == "pretooluse" and tool_name == "CronDelete":
        payload.update(
            canvasAction="remove",
            canvasActivityKind="cron",
        )
    elif event_key == "pretooluse" and tool_name == "CronCreate":
        payload.update(
            canvasAction="start",
            canvasActivityID=f"cron:{session_id}",
            canvasActivityKind="cron",
            canvasTask=tool_input.get("prompt") or "",
            canvasSchedule=tool_input.get("cron"),
        )
    elif (
        event_key in {"pretooluse", "beforeshellexecution"}
        and str(tool_name).lower() in SHELL_TOOL_NAMES
    ):
        command = str(
            tool_input.get("cmd")
            or tool_input.get("command")
            or raw.get("command")
            or ""
        )
        cron = _installed_cron(command)
        if cron:
            schedule, task = cron
            payload.update(
                canvasAction="start",
                canvasActivityID=f"cron:{session_id}:{schedule}:{task}",
                canvasActivityKind="cron",
                canvasTask=task,
                canvasSchedule=schedule,
            )
    elif event_key == "pretooluse" and tool_name in {"Skill", "ScheduleWakeup"}:
        skill = str(tool_input.get("skill") or "").split(":")[-1]
        recurring_kind = (
            "loop" if tool_name == "ScheduleWakeup"
            else skill if skill in {"loop", "schedule", "cron"} else None
        )
        if recurring_kind:
            payload.update(
                canvasAction="start",
                canvasActivityID=f"{recurring_kind}:{session_id}",
                canvasActivityKind=recurring_kind,
                canvasTask=tool_input.get("prompt") or "",
                canvasSchedule=tool_input.get("cron"),
            )
    return payload


def main() -> int:
    provider = sys.argv[1] if len(sys.argv) > 1 else "codex"
    if provider not in {"codex", "claude", "cursor"}:
        return 0
    try:
        raw = json.load(sys.stdin)
        event = normalized_event(raw, provider)
        request = urllib.request.Request(
            BRIDGE_URL,
            data=json.dumps(event).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        timeout = APPROVAL_TIMEOUT_SECONDS if event.get("approvalID") else 0.75
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if event.get("approvalID"):
                result = json.load(response)
                decision = result.get("decision")
                if decision in {"allow", "deny"}:
                    output = {
                        "hookSpecificOutput": {
                            "hookEventName": "PermissionRequest",
                            "decision": {"behavior": decision},
                        }
                    }
                    if decision == "deny":
                        output["hookSpecificOutput"]["decision"]["message"] = (
                            result.get("reason") or "Denied from Ribbit"
                        )
                    print(json.dumps(output))
    except Exception:
        # Observability must never interrupt the provider.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
