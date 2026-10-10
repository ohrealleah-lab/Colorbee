#!/bin/zsh
# Walks Leah through the help book's screenshots (FR-14.6, Docs/HELP-PLAN.md). For each scene it opens Colorbee
# set up for that picture, she takes it with macOS's own screenshot keys, presses Return, and the picture is filed
# in the help book. No Screen Recording permission is needed. Brings Colorbee to the front; run it when the Mac is free.
set -euo pipefail
cd "${0:A:h}/.."

app=build/Build/Products/Release/Colorbee.app/Contents/MacOS/Colorbee
images=Help/Colorbee.help/Contents/Resources/en.lproj/images
sample="TestImages/Help/Sample Screenshot.png"
raw="TestImages/Stage 12/Test Camera.dng"
mkdir -p "$images"

# Where macOS saves screenshots (the Desktop unless changed in the Screenshot app's Options).
shots=$(defaults read com.apple.screencapture location 2>/dev/null || true)
shots=${shots/#\~/$HOME}
[[ -d "$shots" ]] || shots="$HOME/Desktop"

window="press ⇧⌘4, then Space, then Option-click the Colorbee window"
region="press ⇧⌘4, then drag a box around"
# Number | file name | file to open | what to do
scenes=(
    "1|window|$sample|The whole window. $window."
    "2|toolbar|$sample|The toolbar. $region the toolbar (the row of tool buttons along the top)."
    "3|palette-bar|$sample|The palette bar. $region the row of colors under the toolbar."
    "4|auto-redact|$sample|The Auto-Redact sheet. Wait until it lists what it found, then $window."
    "5|before-after|$sample|Before/After. Wait until the black boxes show on the right side, then $window."
    "6|layers|$sample|The Layers panel. $window."
    "7|export-presets|$sample|Settings ▸ Export Presets. Press ⇧⌘4, then Space, then Option-click the Settings window."
    "8|shortcuts|$sample|Settings ▸ Shortcuts. Press ⇧⌘4, then Space, then Option-click the Settings window."
    "9|develop|$raw|The Develop window. Wait for the photo to show, then press ⇧⌘4, then Space, then Option-click the Develop window."
)

echo "Colorbee help screenshots: ${#scenes} pictures, about five minutes."
echo "For each one, Colorbee opens set up for the picture. Take it as described, then come back here and press Return."
echo

for entry in "${scenes[@]}"; do
    IFS='|' read -r number name file instructions <<< "$entry"
    marker=$(mktemp)
    "$app" "$file" -ColorbeeHelpShot "$number" -Appearance light -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
    pid=$!
    echo "[$number of ${#scenes}] $instructions"
    while true; do
        read -r "?Press Return once you've taken it (or type s and Return to skip): " answer
        [[ "$answer" == s ]] && break
        picture=$(find "$shots" -maxdepth 1 -name '*.png' -newer "$marker" -print 2>/dev/null | head -1)
        if [[ -n "$picture" ]]; then
            mv "$picture" "$images/$name.png"
            echo "  Saved as $name.png"
            break
        fi
        echo "  No new screenshot in $shots yet. Take it, then press Return."
    done
    rm -f "$marker"
    # This copy was started by the script, so closing it can't touch the Colorbee you're using.
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo
done
echo "Done. The pictures are in $images."
