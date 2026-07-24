#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_root/ThirdPartyLicenses"
ghostty_version="1.3.1"
ghostty_sha256="3349d25600ffbda281197a18314f7d18791969cffe9474f0ff16a45a9ebfccdb"
zig_bin="/opt/homebrew/opt/zig@0.15/bin/zig"

if [[ ! -x "$zig_bin" ]]; then
    echo "ribbit: license collection requires Zig 0.15.2. Install it with: brew install zig@0.15" >&2
    exit 1
fi

work_dir="$(mktemp -d /tmp/ribbit-licenses.XXXXXX)"
trap '/bin/rm -rf "$work_dir"' EXIT
archive="$work_dir/ghostty-$ghostty_version.tar.gz"
source_dir="$work_dir/ghostty-$ghostty_version"

curl -4 -fsSL --retry 3 \
    "https://release.files.ghostty.org/$ghostty_version/ghostty-$ghostty_version.tar.gz" \
    -o "$archive"

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$ghostty_sha256" ]]; then
    echo "ribbit: Ghostty source checksum did not match while collecting licenses." >&2
    exit 1
fi

tar -xzf "$archive" -C "$work_dir"

# Ensure the pinned dependencies are present in Zig's package cache.
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
        -Demit-helpgen=false >/dev/null
)

zig_cache="$HOME/.cache/zig/p"
staging="$work_dir/licenses"
mkdir -p "$staging"

copy_license() {
    local source="$1"
    local destination="$2"
    if [[ ! -f "$source" ]]; then
        echo "ribbit: expected license file is missing: $source" >&2
        exit 1
    fi
    cp "$source" "$staging/$destination"
}

copy_license "$source_dir/LICENSE" "Ghostty-MIT.txt"
copy_license "$zig_cache/N-V-__8AAKLKpwC4H27Ps_0iL3bPkQb-z6ZVSrB-x_3EEkub/docs/FTL.TXT" "FreeType-FTL.txt"
copy_license "$zig_cache/N-V-__8AAJrvXQCqAT8Mg9o_tk6m0yf5Fz-gCNEOKLyTSerD/LICENSE" "libpng-LICENSE.txt"
copy_license "$zig_cache/N-V-__8AAB0eQwD-0MdOEBmz7intriBReIsIDNlukNVoNu6o/LICENSE" "zlib-LICENSE.txt"
copy_license "$zig_cache/N-V-__8AAHjwMQDBXnLq3Q2QhaivE0kE2aD138vtX2Bq1g7c/COPYING" "Oniguruma-COPYING.txt"
copy_license "$zig_cache/N-V-__8AABzkUgISeKGgXAzgtutgJsZc0-kkeqBBscJgMkvy/LICENSE.txt" "glslang-LICENSE.txt"
copy_license "$zig_cache/N-V-__8AANb6pwD7O1WG6L5nvD_rNMvnSc9Cpg1ijSlTYywv/LICENSE" "SPIRV-Cross-Apache-2.0.txt"
copy_license "$zig_cache/N-V-__8AAPlZGwBEa-gxrcypGBZ2R8Bse4JYSfo_ul8i2jlG/LICENSE" "sentry-native-MIT.txt"
copy_license "$zig_cache/N-V-__8AALw2uwF_03u4JRkZwRLc3Y9hakkYV7NKRR9-RIZJ/LICENSE" "Breakpad-BSD-3-Clause.txt"
copy_license "$zig_cache/N-V-__8AAGmZhABbsPJLfbqrh6JTHsXhY6qCaLAQyx25e0XE/LICENSE" "Highway-Apache-2.0.txt"
copy_license "$zig_cache/N-V-__8AAGmZhABbsPJLfbqrh6JTHsXhY6qCaLAQyx25e0XE/LICENSE-BSD3" "Highway-BSD-3-Clause.txt"
copy_license "$zig_cache/N-V-__8AAHffAgDU0YQmynL8K35WzkcnMUmBVQHQ0jlcKpjH/LICENSE" "utf8cpp-Boost-1.0.txt"
copy_license "$zig_cache/N-V-__8AAEbOfQBnvcFcCX2W5z7tDaN8vaNZGamEQtNOe0UI/LICENSE.txt" "Dear-ImGui-MIT.txt"
copy_license "$zig_cache/N-V-__8AAAzZywE3s51XfsLbP9eyEw57ae9swYB9aGB6fCMs/LICENSE" "Wuffs-LICENSE.txt"
copy_license "$zig_cache/N-V-__8AAAzZywE3s51XfsLbP9eyEw57ae9swYB9aGB6fCMs/LICENSE-MIT" "Wuffs-MIT.txt"
copy_license "$zig_cache/N-V-__8AAAzZywE3s51XfsLbP9eyEw57ae9swYB9aGB6fCMs/LICENSE-APACHE" "Wuffs-Apache-2.0.txt"
copy_license "$zig_cache/N-V-__8AAMVLTABmYkLqhZPLXnMl-KyN38R8UVYqGrxqO26s/LICENSE" "Nerd-Fonts-MIT.txt"
copy_license "$zig_cache/libxev-0.0.0-86vtc4IcEwCqEYxEYoN_3KXmc6A9VLcm22aVImfvecYs/LICENSE" "libxev-MIT.txt"
copy_license "$zig_cache/zig_objc-0.0.0-Ir_Sp5gTAQCvxxR7oVIrPXxXwsfKgVP7_wqoOQrZjFeK/LICENSE" "zig-objc-MIT.txt"
copy_license "$zig_cache/uucode-0.2.0-ZZjBPqZVVABQepOqZHR7vV_NcaN-wats0IB6o-Exj6m9/LICENSE.md" "uucode-MIT.md"

mkdir -p "$staging/uucode"
curl -fsSL "https://raw.githubusercontent.com/jacobsandlund/uucode/v0.2.0/licenses/LICENSE_Bjoern_Hoehrmann" \
    -o "$staging/uucode/LICENSE_Bjoern_Hoehrmann.txt"
curl -fsSL "https://raw.githubusercontent.com/jacobsandlund/uucode/v0.2.0/licenses/LICENSE_unicode" \
    -o "$staging/uucode/LICENSE_unicode.txt"

curl -fsSL "https://raw.githubusercontent.com/simdutf/simdutf/v5.2.8/LICENSE-MIT" \
    -o "$staging/simdutf-MIT.txt"
curl -fsSL "https://raw.githubusercontent.com/dearimgui/dear_bindings/v0.17/LICENSE.txt" \
    -o "$staging/Dear-Bindings-MIT.txt"
curl -fsSL "https://raw.githubusercontent.com/vancluever/z2d/v0.10.0/LICENSE" \
    -o "$staging/z2d-LICENSE.txt"
curl -fsSL "https://raw.githubusercontent.com/vancluever/z2d/v0.10.0/COPYING" \
    -o "$staging/z2d-MPL-2.0.txt"

# Sentry Native vendors MPack's MIT-licensed amalgamation.
sed -n '2,23p' \
    "$zig_cache/N-V-__8AAPlZGwBEa-gxrcypGBZ2R8Bse4JYSfo_ul8i2jlG/vendor/mpack.h" \
    | sed 's/^ \* \{0,1\}//; s/^ \*$/ /' \
    > "$staging/MPack-MIT.txt"

/bin/rm -rf "$output_dir"
mv "$staging" "$output_dir"
echo "ribbit: collected $(find "$output_dir" -type f | wc -l | tr -d ' ') third-party license files."
