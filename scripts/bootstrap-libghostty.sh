#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
framework="$project_root/Vendor/GhosttyKit.xcframework"
resources="$project_root/Vendor/GhosttyResources"
version="1.3.1"
expected_sha256="3349d25600ffbda281197a18314f7d18791969cffe9474f0ff16a45a9ebfccdb"
zig_bin="/opt/homebrew/opt/zig@0.15/bin/zig"

if [[ -d "$framework" && -d "$resources/ghostty" && -d "$resources/terminfo" ]]; then
    exit 0
fi

if [[ ! -x "$zig_bin" ]]; then
    echo "ribbit: libghostty requires Zig 0.15.2. Install it with: brew install zig@0.15" >&2
    exit 1
fi

work_dir="$(mktemp -d /tmp/ribbit-libghostty.XXXXXX)"
trap '/bin/rm -rf "$work_dir"' EXIT
archive="$work_dir/ghostty-$version.tar.gz"
source_dir="$work_dir/ghostty-$version"

echo "ribbit: downloading libghostty $version…"
curl -4 -fL --retry 3 \
    "https://release.files.ghostty.org/$version/ghostty-$version.tar.gz" \
    -o "$archive"

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "ribbit: libghostty source checksum did not match." >&2
    exit 1
fi

tar -xzf "$archive" -C "$work_dir"
echo "ribbit: building the native GhosttyKit framework…"
(
    cd "$source_dir"
    "$zig_bin" build \
        -Doptimize=ReleaseFast \
        -Demit-xcframework=true \
        -Dxcframework-target=native \
        -Demit-macos-app=false \
        -Demit-docs=false \
        -Demit-bench=false \
        -Demit-test-exe=false \
        -Demit-helpgen=false
)

mkdir -p "$project_root/Vendor"
/bin/rm -rf "$framework" "$resources"
cp -R "$source_dir/macos/GhosttyKit.xcframework" "$framework"
mkdir -p "$resources"
cp -R "$source_dir/zig-out/share/ghostty" "$resources/ghostty"
cp -R "$source_dir/zig-out/share/terminfo" "$resources/terminfo"
echo "ribbit: libghostty $version is ready."
