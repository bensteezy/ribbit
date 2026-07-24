import Foundation

enum RibbitCommandInstaller {
    static func install(in supportURL: URL, fileManager: FileManager = .default) throws -> URL {
        let binURL = supportURL.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(
            at: binURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let commandURL = binURL.appendingPathComponent("ribbit")
        let script = #"""
        #!/bin/sh
        set -eu

        command_name="${1:-}"
        case "$command_name" in
          save)
            if [ "${RIBBIT_PROJECT:-0}" != "1" ] || [ -z "${RIBBIT_SAVE_REQUEST:-}" ]; then
              printf '%s\n' 'ribbit: this terminal is not attached to a project' >&2
              exit 1
            fi
            shift
            request_tmp="${RIBBIT_SAVE_REQUEST}.tmp.$$"
            printf '%s\n' "$*" > "$request_tmp"
            mv "$request_tmp" "$RIBBIT_SAVE_REQUEST"
            printf '%s\n' 'ribbit: saving terminal transcript…'
            ;;
          context)
            context_index="${RIBBIT_CONTEXT_INDEX:-}"
            if [ -z "$context_index" ] && [ -n "${TMUX:-}" ]; then
              tmux_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
              terminal_id="$(printf '%s' "$tmux_session" | tail -c 36)"
              workspace_key="${tmux_session#ribbit-}"
              workspace_key="${workspace_key%-$terminal_id}"
              if [ -n "$terminal_id" ] && [ "$workspace_key" != "$tmux_session" ]; then
                context_index="$HOME/Library/Application Support/ribbit/context/$workspace_key/$terminal_id.json"
              fi
            fi
            if [ -z "$context_index" ]; then
              printf '%s\n' 'ribbit: context is unavailable in this terminal' >&2
              exit 1
            fi
            shift
            context_command="${1:-list}"
            if [ "$#" -gt 0 ]; then shift; fi
            /usr/bin/python3 - "$context_index" "$context_command" "$*" <<'PY'
        import glob
        import json
        import os
        import re
        import sys

        index_path, command, query = sys.argv[1:4]
        try:
            with open(index_path, encoding="utf-8") as handle:
                links = json.load(handle).get("links", [])
        except (OSError, ValueError):
            links = []

        if command == "list":
            if not links:
                print("ribbit: no linked context")
            for link in links:
                print(f"{link['id']}\t{link['kind']}\t{link['title']}")
            raise SystemExit(0)

        if command != "read" or not query.strip():
            print("usage: ribbit context list | ribbit context read <node-id-or-title>", file=sys.stderr)
            raise SystemExit(2)

        needle = query.strip().lower()
        matches = [
            link for link in links
            if link["id"].lower() == needle
            or link["id"].lower().startswith(needle)
            or link["title"].lower() == needle
        ]
        if len(matches) != 1:
            print(
                "ribbit: linked context not found"
                if not matches else "ribbit: context name is ambiguous; use the node id",
                file=sys.stderr,
            )
            raise SystemExit(1)

        link = matches[0]
        path = link["contentPath"]
        if link["kind"] == "note":
            try:
                with open(path, encoding="utf-8") as handle:
                    sys.stdout.write(handle.read())
            except OSError as error:
                print(f"ribbit: {error}", file=sys.stderr)
                raise SystemExit(1)
            raise SystemExit(0)

        raw = b""
        for segment in sorted(glob.glob(os.path.join(path, "segment-*.raw"))):
            try:
                with open(segment, "rb") as handle:
                    raw += handle.read()
            except OSError:
                pass
        text = raw.decode("utf-8", errors="replace")
        text = re.sub(r"\x1b\].*?(?:\x07|\x1b\\\\)", "", text, flags=re.S)
        text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
        rendered = []
        for line in text.split("\n"):
            line = line.split("\r")[-1]
            while "\b" in line:
                line = re.sub(r".\b", "", line, count=1)
            rendered.append(line.rstrip())
        sys.stdout.write("\n".join(rendered).rstrip() + ("\n" if rendered else ""))
        PY
            ;;
          *)
            printf '%s\n' 'usage: ribbit save [note-name] | ribbit context list | ribbit context read <node>' >&2
            exit 2
            ;;
        esac
        """#
        try script.write(to: commandURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandURL.path)
        return binURL
    }
}
