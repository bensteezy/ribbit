#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

if (( $# == 0 )); then
    "$project_root/scripts/build-app.sh"
    source_app="$project_root/build/ribbit.app"
else
    source_app="$1"
    if [[ ! -d "$source_app" ]]; then
        echo "app bundle not found: $source_app" >&2
        exit 66
    fi
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$source_app/Contents/Info.plist")
output_dmg="${2:-$project_root/build/Ribbit-$version.dmg}"
volume_name="Ribbit"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/ribbit-dmg.XXXXXX")"
staging_dir="$work_dir/staging"
rw_dmg="$work_dir/Ribbit-rw.dmg"
mount_point=""

cleanup() {
    if [[ -n "$mount_point" && -d "$mount_point" ]]; then
        hdiutil detach "$mount_point" -quiet || hdiutil detach "$mount_point" -force -quiet || true
    fi
    /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$staging_dir/.background"
ditto "$source_app" "$staging_dir/Ribbit.app"
ln -s /Applications "$staging_dir/Applications"
cp "$project_root/App/Ribbit.icns" "$staging_dir/.VolumeIcon.icns"
swift "$project_root/scripts/generate-dmg-background.swift" \
    "$staging_dir/.background/background.png"

hdiutil create \
    -srcfolder "$staging_dir" \
    -volname "$volume_name" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$rw_dmg" >/dev/null

attach_output="$(hdiutil attach "$rw_dmg" -readwrite -noverify -noautoopen)"
mount_point="$(print -r -- "$attach_output" | tail -1 | sed $'s/.*\t//')"
mounted_volume_name="${mount_point:t}"

SetFile -a V "$mount_point/.background" "$mount_point/.VolumeIcon.icns"
SetFile -a C "$mount_point"

osascript - "$mounted_volume_name" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set pathbar visible of container window to false
            set sidebar width of container window to 0
            set bounds of container window to {180, 180, 840, 600}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 112
            set text size of theViewOptions to 13
            set background picture of theViewOptions to file ".background:background.png"
            set position of item "Ribbit.app" of container window to {180, 229}
            set position of item "Applications" of container window to {480, 229}
            close
            open
            update without registering applications
            delay 3
        end tell
    end tell
end run
APPLESCRIPT

for attempt in {1..20}; do
    [[ -f "$mount_point/.DS_Store" ]] && break
    sleep 0.5
done
if [[ ! -f "$mount_point/.DS_Store" ]]; then
    echo "Finder did not save the DMG window layout" >&2
    exit 1
fi

sync
hdiutil detach "$mount_point" -quiet
mount_point=""

mkdir -p "$(dirname "$output_dmg")"
/bin/rm -f "$output_dmg"
hdiutil convert "$rw_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$output_dmg" >/dev/null
hdiutil verify "$output_dmg" >/dev/null

verify_output="$(hdiutil attach "$output_dmg" -readonly -noverify -noautoopen)"
mount_point="$(print -r -- "$verify_output" | tail -1 | sed $'s/.*\t//')"
test -d "$mount_point/Ribbit.app"
test -L "$mount_point/Applications"
test "$(readlink "$mount_point/Applications")" = "/Applications"
codesign --verify --deep --strict "$mount_point/Ribbit.app"
hdiutil detach "$mount_point" -quiet
mount_point=""

echo "built and verified $output_dmg"
