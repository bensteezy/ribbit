#!/bin/zsh
set -euo pipefail

app_bundle="${1:-}"
if [[ -z "$app_bundle" || ! -d "$app_bundle" ]]; then
    echo "usage: $0 /path/to/ribbit.app" >&2
    exit 1
fi

resources="$app_bundle/Contents/Resources"
required=(
    "LICENSE.txt"
    "THIRD_PARTY_NOTICES.md"
    "ThirdPartyLicenses/Ghostty-MIT.txt"
    "ThirdPartyLicenses/FreeType-FTL.txt"
    "ThirdPartyLicenses/libpng-LICENSE.txt"
    "ThirdPartyLicenses/zlib-LICENSE.txt"
    "ThirdPartyLicenses/Oniguruma-COPYING.txt"
    "ThirdPartyLicenses/glslang-LICENSE.txt"
    "ThirdPartyLicenses/SPIRV-Cross-Apache-2.0.txt"
    "ThirdPartyLicenses/sentry-native-MIT.txt"
    "ThirdPartyLicenses/Breakpad-BSD-3-Clause.txt"
    "ThirdPartyLicenses/MPack-MIT.txt"
    "ThirdPartyLicenses/simdutf-MIT.txt"
    "ThirdPartyLicenses/Highway-Apache-2.0.txt"
    "ThirdPartyLicenses/utf8cpp-Boost-1.0.txt"
    "ThirdPartyLicenses/Dear-ImGui-MIT.txt"
    "ThirdPartyLicenses/Dear-Bindings-MIT.txt"
    "ThirdPartyLicenses/Wuffs-LICENSE.txt"
    "ThirdPartyLicenses/Nerd-Fonts-MIT.txt"
    "ThirdPartyLicenses/libxev-MIT.txt"
    "ThirdPartyLicenses/zig-objc-MIT.txt"
    "ThirdPartyLicenses/uucode-MIT.md"
    "ThirdPartyLicenses/z2d-LICENSE.txt"
    "ThirdPartyLicenses/z2d-MPL-2.0.txt"
)

for relative_path in "${required[@]}"; do
    if [[ ! -s "$resources/$relative_path" ]]; then
        echo "ribbit: release is missing required notice: $relative_path" >&2
        exit 1
    fi
done

if [[ -d "$resources/ghostty/themes" ]]; then
    echo "ribbit: unused third-party themes must not be included in the release." >&2
    exit 1
fi

echo "ribbit: release license bundle verified."
