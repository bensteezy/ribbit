#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$project_root/build/ribbit.app"

cd "$project_root"
"$project_root/scripts/bootstrap-libghostty.sh"
swift scripts/generate-ribbit-icon.swift
swift build -c release

/bin/rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_root/.build/release/Ribbit" "$app_bundle/Contents/MacOS/ribbit"
cp "$project_root/App/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$project_root/App/Ribbit.icns" "$app_bundle/Contents/Resources/ribbit.icns"
mkdir -p "$app_bundle/Contents/Resources/ghostty"
cp -R "$project_root/Vendor/GhosttyResources/ghostty/shell-integration" "$app_bundle/Contents/Resources/ghostty/shell-integration"
cp -R "$project_root/Vendor/GhosttyResources/terminfo" "$app_bundle/Contents/Resources/terminfo"
mkdir -p "$app_bundle/Contents/Resources/RibbitIntegration"
cp "$project_root/scripts/install-ribbit-hooks.sh" "$app_bundle/Contents/Resources/RibbitIntegration/install-ribbit-hooks.sh"
cp "$project_root/integrations/ribbit_event.py" "$app_bundle/Contents/Resources/RibbitIntegration/ribbit_event.py"
cp "$project_root/LICENSE" "$app_bundle/Contents/Resources/LICENSE.txt"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$app_bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$project_root/ThirdPartyLicenses" "$app_bundle/Contents/Resources/ThirdPartyLicenses"

plutil -lint "$app_bundle/Contents/Info.plist"
codesign --force --deep --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
"$project_root/scripts/verify-release-licenses.sh" "$app_bundle"
echo "built $app_bundle"
