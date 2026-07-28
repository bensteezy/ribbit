#!/bin/zsh
set -euo pipefail

mode="${1:---dry-run}"
if [[ "$mode" != "--dry-run" && "$mode" != "--install" ]]; then
  print -u2 "usage: install-ribbit-hooks.sh [--dry-run|--install]"
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$script_dir/ribbit_event.py" ]]; then
  event_script="$script_dir/ribbit_event.py"
else
  event_script="$(cd "$script_dir/.." && pwd)/integrations/ribbit_event.py"
fi
if [[ ! -f "$event_script" ]]; then
  print -u2 "ribbit integration script is missing."
  exit 1
fi

RIBBIT_EVENT_SCRIPT="$event_script" RIBBIT_INSTALL_MODE="$mode" /usr/bin/env python3 - <<'PY'
from __future__ import annotations

import copy
import json
import os
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

mode = os.environ["RIBBIT_INSTALL_MODE"]
event_script = Path(os.environ["RIBBIT_EVENT_SCRIPT"]).resolve()
hook_script = f'/usr/bin/env python3 "{event_script}"'


def is_owned_handler(handler: dict, provider: str) -> bool:
    command = handler.get("command", "")
    known_script = any(
        name in command
        for name in ("ribbit_event.py", "noot_event.py", "tux_event.py")
    )
    return known_script and command.rstrip().endswith(f" {provider}")


def backup(path: Path) -> None:
    if not path.exists():
        return
    stamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
    destination = path.with_name(path.name + ".ribbit-backup-" + stamp)
    destination.write_text(path.read_text())
    print(f"backup: {destination}")


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text())


targets = {
    "codex": (
        Path.home() / ".codex" / "hooks.json",
        [
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PermissionRequest", "PreCompact", "PostCompact", "Stop",
        ],
    ),
}


def claude_version() -> tuple[int, int, int] | None:
    candidates = []
    discovered = shutil.which("claude")
    if discovered:
        candidates.append(Path(discovered))
    candidates.extend(
        sorted(
            (Path.home() / ".nvm/versions/node").glob("*/bin/claude"),
            reverse=True,
        )
    )
    candidates.extend([
        Path("/opt/homebrew/bin/claude"),
        Path("/usr/local/bin/claude"),
        Path.home() / ".local/bin/claude",
        Path.home() / ".claude/local/claude",
    ])
    for candidate in candidates:
        if not candidate.exists():
            continue
        try:
            output = subprocess.run(
                [str(candidate), "--version"],
                capture_output=True,
                text=True,
                timeout=2,
                check=True,
            ).stdout
            match = re.search(r"(\d+)\.(\d+)\.(\d+)", output)
            if match:
                return tuple(map(int, match.groups()))
        except Exception:
            pass
    return None


def claude_events() -> list[str]:
    events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "Notification", "Stop", "SubagentStop",
        "SessionEnd", "PreCompact",
    ]
    version = claude_version()
    if version is None:
        return events
    if version >= (2, 0, 0):
        events.append("PostToolUseFailure")
    if version >= (2, 0, 43):
        events.append("SubagentStart")
    if version >= (2, 1, 76):
        events.append("PostCompact")
    if version >= (2, 1, 78):
        events.append("StopFailure")
    if version >= (2, 1, 88):
        events.append("PermissionDenied")
    return events


targets["claude"] = (
    Path.home() / ".claude" / "settings.json",
    claude_events(),
)

for provider, (path, events) in targets.items():
    existing = read_json(path)
    updated = copy.deepcopy(existing)
    hooks = updated.setdefault("hooks", {})
    command = f"{hook_script} {provider}"
    changes = []
    for event in events:
        timeout = 305 if provider == "claude" and event == "PermissionRequest" else 2
        groups = hooks.setdefault(event, [])
        owned = [
            handler
            for group in groups
            for handler in group.get("hooks", [])
            if is_owned_handler(handler, provider)
        ]
        if owned:
            for handler in owned:
                if (
                    handler.get("command") != command
                    or handler.get("timeout") != timeout
                    or handler.get("type") != "command"
                ):
                    handler.update(command=command, timeout=timeout, type="command")
                    changes.append(f"repair {event}")
            continue
        group = {"hooks": [{"type": "command", "command": command, "timeout": timeout}]}
        if event == "Notification":
            group["matcher"] = "permission_prompt|idle_prompt|elicitation_dialog"
        groups.append(group)
        changes.append(f"add {event}")
    if not changes:
        print(f"{provider}: ready")
        continue
    print(f"{provider}: " + ", ".join(changes))
    if mode == "--install":
        path.parent.mkdir(parents=True, exist_ok=True)
        backup(path)
        path.write_text(json.dumps(updated, indent=2) + "\n")
        print(f"{provider}: installed")

cursor_path = Path.home() / ".cursor" / "hooks.json"
cursor_events = [
    "sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse",
    "postToolUseFailure", "preCompact", "stop", "sessionEnd",
]
cursor_updated = copy.deepcopy(read_json(cursor_path))
cursor_updated.setdefault("version", 1)
cursor_hooks = cursor_updated.setdefault("hooks", {})
cursor_command = f"{hook_script} cursor"
cursor_changes = []
for event in cursor_events:
    handlers = cursor_hooks.setdefault(event, [])
    owned = [handler for handler in handlers if is_owned_handler(handler, "cursor")]
    if owned:
        for handler in owned:
            if handler.get("command") != cursor_command:
                handler.update(command=cursor_command, timeout=2)
                cursor_changes.append(f"repair {event}")
        continue
    handlers.append({"command": cursor_command, "timeout": 2})
    cursor_changes.append(f"add {event}")

if not cursor_changes:
    print("cursor: ready")
else:
    print("cursor: " + ", ".join(cursor_changes))
    if mode == "--install":
        cursor_path.parent.mkdir(parents=True, exist_ok=True)
        backup(cursor_path)
        cursor_path.write_text(json.dumps(cursor_updated, indent=2) + "\n")
        print("cursor: installed")
PY
