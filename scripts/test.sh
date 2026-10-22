#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed (no Xcode),
# Swift Testing lives outside the default search path and its Foundation
# overlay module is missing, so point at the framework and skip overlays.
set -euo pipefail
cd "${0:A:h}/.."

if xcode-select -p | grep -q CommandLineTools; then
    F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    exec swift test \
        -Xswiftc "-F$F" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker "-F$F" -Xlinker -rpath -Xlinker "$F" "$@"
fi
exec swift test "$@"
