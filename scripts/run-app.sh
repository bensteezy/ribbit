#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
"$project_root/scripts/build-app.sh"
open "$project_root/build/ribbit.app"
