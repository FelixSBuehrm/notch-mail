#!/bin/zsh
# Builds Notch Mail and installs it as /Applications/NotchMail.app, then starts it.
# On its first start from there it adds itself to Login Items.
# Usage: scripts/install.sh
set -euo pipefail
cd "${0:A:h}/.."

scripts/bundle.sh
DEST=/Applications/NotchMail.app

pkill -x NotchMail 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
ditto build/NotchMail.app "$DEST"
open "$DEST"
echo "Installed $DEST"
