#!/bin/zsh
# Signs build/NotchMail.app with a local, self-signed identity that stays the same
# across builds. macOS then remembers "Always Allow" for Keychain items instead of
# asking again after every build (ad-hoc signatures change with every build).
#
# The identity lives in its own keychain, unlocked with a random password kept in
# the login keychain. Nothing here is trusted system-wide; it only makes the app's
# signature stable. Usage: scripts/signing.sh <path-to-app>
set -euo pipefail

APP="$1"
NAME="Notch Mail Local Signing"
KEYCHAIN="$HOME/Library/Keychains/notchmail-signing.keychain-db"
PASS_SERVICE="notchmail.signing-keychain"

password() { security find-generic-password -s "$PASS_SERVICE" -a "$USER" -w 2>/dev/null; }

create_identity() {
    local dir pass
    dir=$(mktemp -d)
    trap "rm -rf '$dir'" EXIT
    pass=$(openssl rand -hex 24)
    cat > "$dir/cfg" <<CFG
[req]
distinguished_name=dn
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CFG
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/key.pem" -out "$dir/cert.pem" \
        -days 3650 -config "$dir/cfg" -extensions ext 2>/dev/null
    openssl pkcs12 -export -legacy -inkey "$dir/key.pem" -in "$dir/cert.pem" \
        -out "$dir/id.p12" -passout "pass:$pass" 2>/dev/null
    security add-generic-password -U -s "$PASS_SERVICE" -a "$USER" -w "$pass"
    security create-keychain -p "$pass" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"   # no auto-lock timeout
    security unlock-keychain -p "$pass" "$KEYCHAIN"
    security import "$dir/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -k "$pass" "$KEYCHAIN" >/dev/null
    echo "Created signing identity \"$NAME\""
}

if [[ ! -f "$KEYCHAIN" ]] || ! password >/dev/null; then
    rm -f "$KEYCHAIN"
    create_identity
fi
security unlock-keychain -p "$(password)" "$KEYCHAIN"
codesign --force --sign "$NAME" --keychain "$KEYCHAIN" "$APP"
