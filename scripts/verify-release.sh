#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

cd "$project_root"
"$project_root/scripts/verify-public-source.sh"
swift test
"$project_root/scripts/verify-terminal-input.py"
"$project_root/scripts/build-app.sh"

echo "ribbit: release verification passed."
