#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$project_root"

matches=$(
    /usr/bin/grep -R -I -n -E \
        --exclude-dir=.git \
        --exclude-dir=.build \
        --exclude-dir=build \
        --exclude-dir=Vendor \
        --exclude-dir=.hallmark \
        --exclude='*.icns' \
        'bensteele|Bens-MacBook|/Users/[A-Za-z0-9._-]+' \
        . 2>/dev/null \
        | /usr/bin/grep -v '/Users/Shared/' \
        | /usr/bin/grep -v '^\./scripts/verify-public-source\.sh:' \
        || true
)
if [ -n "$matches" ]; then
    echo "ribbit: public source contains a personal identifier or private home path:" >&2
    echo "$matches" >&2
    exit 1
fi

secret_files=$(
    /usr/bin/find . \
        \( -path './.git' -o -path './.build' -o -path './build' -o -path './Vendor' -o -path './.hallmark' \) -prune \
        -o -type f \
        \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.p12' \
           -o -name '*.mobileprovision' -o -name 'id_rsa' -o -name 'id_ed25519' \) \
        -print
)
if [ -n "$secret_files" ]; then
    echo "ribbit: public source contains a credential-shaped file:" >&2
    echo "$secret_files" >&2
    exit 1
fi

if [ -d .hallmark ] && ! git check-ignore -q .hallmark; then
    echo "ribbit: .hallmark must remain excluded from public source." >&2
    exit 1
fi

echo "ribbit: public source privacy checks passed."
