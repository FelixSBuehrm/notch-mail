#!/bin/zsh
# Records docs/images/demo.gif: a scripted tour (--tour) through the notch with
# demo mail only. A made-up desktop window covers the top of the screen while
# recording, and only the area around the notch is kept, so nothing from your
# real screen ends up in the GIF. Needs ffmpeg and Screen Recording permission.
# Your installed Notch Mail is paused for the ~40 s and started again after.
# Usage: scripts/screenshots/record.sh
set -euo pipefail
cd "${0:A:h}/../.."

TMP=$(mktemp -d)
backdrop_pid=""
was_running=no
cleanup() {
    # Whatever happens: the backdrop goes away and your own Notch Mail comes back.
    [[ -n "$backdrop_pid" ]] && kill "$backdrop_pid" 2>/dev/null || true
    pkill -f "build/NotchMail.app/Contents/MacOS/NotchMail" 2>/dev/null || true
    [[ "$was_running" == yes ]] && open /Applications/NotchMail.app
    rm -rf "$TMP"
}
trap cleanup EXIT
swiftc -O scripts/screenshots/compose.swift -o "$TMP/compose"
swiftc -O scripts/screenshots/backdrop.swift -o "$TMP/backdrop"
scripts/bundle.sh >/dev/null

"$TMP/compose" --background 1470 500 "$TMP/bg.png"
pgrep -x NotchMail >/dev/null && was_running=yes
osascript -e 'quit app "NotchMail"' 2>/dev/null || true
sleep 1

# The backdrop stays up far longer than needed; it's closed right after recording.
"$TMP/backdrop" "$TMP/bg.png" 600 > "$TMP/geometry" &
backdrop_pid=$!
sleep 1.5
read -r points_w points_h scale < "$TMP/geometry"
pixels_w=$((points_w * scale))

# The avfoundation "Capture screen" device of the notched display.
device=""
for index in $(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | sed -nE 's/.*\[([0-9]+)\] Capture screen.*/\1/p'); do
    size=$(ffmpeg -hide_banner -f avfoundation -capture_cursor 0 -i "$index:none" -frames:v 1 -f null - 2>&1 | grep -oE "[0-9]{3,5}x[0-9]{3,5}" | head -1)
    [[ "${size%x*}" == "$pixels_w" ]] && device=$index && break
done
[[ -n "$device" ]] || { echo "No screen recording device for the notched display"; exit 1; }

crop_w=$((760 * scale)); crop_h=$((500 * scale)); crop_x=$(((pixels_w - crop_w) / 2))
ffmpeg -hide_banner -loglevel error -f avfoundation -capture_cursor 0 -framerate 30 -pixel_format nv12 -i "$device:none" -t 40 \
    -vf "crop=$crop_w:$crop_h:$crop_x:0" -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p "$TMP/tour.mp4" &
recorder=$!
sleep 1
open -n build/NotchMail.app --args --capturable --demo-only --pin --tour --demo 0
wait $recorder
kill "$backdrop_pid" 2>/dev/null || true
backdrop_pid=""

ffmpeg -hide_banner -loglevel error -y -ss 3.3 -to 33.5 -i "$TMP/tour.mp4" \
    -vf "fps=10,scale=680:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    -loop 0 docs/images/demo.gif
echo "docs/images/demo.gif"
