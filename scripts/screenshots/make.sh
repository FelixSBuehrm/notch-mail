#!/bin/zsh
# Regenerates docs/images/*.png from demo mail only: no account, no Keychain,
# no real inbox. Each shot captures just the notch window and puts it on a
# made-up desktop, so nothing personal from your screen can end up in it.
# Usage: scripts/screenshots/make.sh
set -euo pipefail
cd "${0:A:h}/../.."

TOOLS=$(mktemp -d)
trap "rm -rf '$TOOLS'" EXIT
swiftc -O scripts/screenshots/winid.swift -o "$TOOLS/winid"
swiftc -O scripts/screenshots/compose.swift -o "$TOOLS/compose"
swiftc -O scripts/screenshots/social.swift -o "$TOOLS/social"
scripts/bundle.sh >/dev/null

shot() {
    local name=$1 wait=$2 size=$3
    shift 3
    open -n build/NotchMail.app --args --capturable --demo-only --pin "$@"
    sleep "$wait"
    local pid=$(pgrep -f "build/NotchMail.app/Contents/MacOS/NotchMail" | head -1)
    screencapture -x -o -l "$("$TOOLS/winid" "$pid")" "$TOOLS/$name.png"
    kill "$pid"
    sleep 0.8
    "$TOOLS/compose" "$TOOLS/$name.png" "docs/images/$name.png" ${=size}
    echo "docs/images/$name.png"
}

mkdir -p docs/images
# Gallery shots share one size (extra, width, height in points); the list is the wide hero.
gallery="0 760 500"
shot alert 3.4 "$gallery" --demo 2
shot list 4.5 "70" --demo 6 --open-list
shot html 7 "$gallery" --demo 1 --open-first
shot code 4 "$gallery" --demo 2 --open-first
shot reply 5.5 "$gallery" --demo 3 --open-reply --auto-draft "Sounds good, Thursday 2pm works. I'll add my notes to the doc before."
"$TOOLS/social" docs/images/icon.png docs/images/list.png docs/images/social.png
echo "docs/images/social.png (upload it under Settings → General → Social preview)"
