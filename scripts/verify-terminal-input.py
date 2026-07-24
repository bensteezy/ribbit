#!/usr/bin/env python3
"""Verify that direct PTY and tmux-backed terminals preserve Ribbit input bytes."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import pathlib
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
import uuid


CASES = [
    ("text", b"codxe"),
    ("left", b"\x1b[D"),
    ("right", b"\x1b[C"),
    ("up", b"\x1b[A"),
    ("down", b"\x1b[B"),
    ("option-left", b"\x1bb"),
    ("option-right", b"\x1bf"),
    ("tab", b"\x09"),
    ("shift-tab", b"\x1b[Z"),
    ("backspace", b"\x7f"),
    ("forward-delete", b"\x1b[3~"),
    ("home", b"\x1b[H"),
    ("end", b"\x1b[F"),
    ("page-up", b"\x1b[5~"),
    ("page-down", b"\x1b[6~"),
    ("escape", b"\x1b"),
    ("control-a", b"\x01"),
    ("control-e", b"\x05"),
    ("shift-return", b"\x0a"),
    ("option-return", b"\x1b\x0d"),
    ("return", b"\x0d"),
]
EXPECTED = b"".join(value for _, value in CASES)
MARKER = b"__RIBBIT_INPUT_PROBE_END__"


def wait_for_file(path: pathlib.Path, expected_size: int, timeout: float = 5) -> bytes:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            data = path.read_bytes()
            if len(data) >= expected_size:
                return data
        time.sleep(0.02)
    return path.read_bytes() if path.exists() else b""


def recorder_command(output: pathlib.Path) -> list[str]:
    return [sys.executable, str(pathlib.Path(__file__).resolve()), "--record", str(output)]


def child_setup(slave: int) -> None:
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)


def configure_window(slave: int) -> None:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))


def send_and_drain(process: subprocess.Popen[bytes], master: int) -> None:
    time.sleep(0.15)
    os.write(master, EXPECTED + MARKER)
    deadline = time.monotonic() + 5
    while process.poll() is None and time.monotonic() < deadline:
        readable, _, _ = select.select([master], [], [], 0.05)
        if readable:
            try:
                os.read(master, 65_536)
            except OSError:
                break
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=2)


def capture_direct(output: pathlib.Path) -> bytes:
    master, slave = pty.openpty()
    configure_window(slave)
    try:
        process = subprocess.Popen(
            recorder_command(output),
            stdin=slave,
            stdout=slave,
            stderr=slave,
            close_fds=True,
            preexec_fn=lambda: child_setup(slave),
        )
        send_and_drain(process, master)
        return wait_for_file(output, len(EXPECTED))
    finally:
        os.close(master)
        os.close(slave)


def capture_tmux(tmux: str, output: pathlib.Path) -> bytes:
    socket = f"ribbit-input-{uuid.uuid4().hex}"
    session = "probe"
    environment = dict(os.environ)
    environment["TERM"] = "xterm-256color"
    subprocess.run(
        [tmux, "-L", socket, "new-session", "-d", "-s", session, *recorder_command(output)],
        check=True,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    master, slave = pty.openpty()
    configure_window(slave)
    try:
        process = subprocess.Popen(
            [tmux, "-L", socket, "attach-session", "-t", session],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            close_fds=True,
            env=environment,
            preexec_fn=lambda: child_setup(slave),
        )
        send_and_drain(process, master)
        return wait_for_file(output, len(EXPECTED))
    finally:
        os.close(master)
        os.close(slave)
        subprocess.run(
            [tmux, "-L", socket, "kill-server"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def mismatch(expected: bytes, actual: bytes) -> dict[str, object]:
    first = next(
        (index for index, pair in enumerate(zip(expected, actual)) if pair[0] != pair[1]),
        min(len(expected), len(actual)),
    )
    return {
        "firstMismatch": first,
        "expectedLength": len(expected),
        "actualLength": len(actual),
        "expectedHex": expected.hex(),
        "actualHex": actual.hex(),
    }


def record(output: pathlib.Path) -> int:
    import tty

    tty.setraw(0)
    captured = b""
    while MARKER not in captured:
        chunk = os.read(0, 1024)
        if not chunk:
            return 1
        captured += chunk
    output.write_bytes(captured.split(MARKER, 1)[0])
    return 0


def canonical_tmux_input(value: bytes) -> bytes:
    return value.replace(b"\x1b[1~", b"\x1b[H").replace(b"\x1b[4~", b"\x1b[F")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--record", type=pathlib.Path)
    arguments = parser.parse_args()
    if arguments.record is not None:
        return record(arguments.record)
    tmux = shutil.which("tmux")
    if tmux is None:
        print("ribbit: tmux is unavailable; terminal input probe cannot run.")
        return 2

    with tempfile.TemporaryDirectory(prefix="ribbit-input-") as directory:
        root = pathlib.Path(directory)
        direct = capture_direct(root / "direct.bin")
        through_tmux = capture_tmux(tmux, root / "tmux.bin")

    canonical_tmux = canonical_tmux_input(through_tmux)
    results = {
        "cases": [name for name, _ in CASES],
        "expectedBytes": len(EXPECTED),
        "direct": direct == EXPECTED,
        "tmux": canonical_tmux == EXPECTED,
        "tmuxNormalizedNavigation": through_tmux != canonical_tmux,
    }
    if arguments.json:
        print(json.dumps(results, sort_keys=True))
    else:
        print(
            "ribbit terminal input: "
            f"{len(CASES)} chords / {len(EXPECTED)} bytes; "
            f"direct={'pass' if results['direct'] else 'fail'}; "
            f"tmux={'pass' if results['tmux'] else 'fail'}"
        )
    if direct != EXPECTED:
        print("direct mismatch:", json.dumps(mismatch(EXPECTED, direct)))
    if canonical_tmux != EXPECTED:
        print("tmux mismatch:", json.dumps(mismatch(EXPECTED, canonical_tmux)))
    return 0 if direct == EXPECTED and canonical_tmux == EXPECTED else 1


if __name__ == "__main__":
    raise SystemExit(main())
