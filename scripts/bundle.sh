#!/usr/bin/env bash
# Assembles Toe.app from the release binary and ad-hoc signs it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/build/Toe.app"
config="${1:-release}"

swift build -c "$config" --package-path "$root"
binary="$(swift build -c "$config" --package-path "$root" --show-bin-path)/toe"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/toe"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

# macOS keys Accessibility grants to the code signature. Prefer the stable self-signed
# identity from scripts/dev-cert.sh so the grant survives a rebuild; fall back to ad-hoc
# signing, which changes on every build and makes macOS re-ask.
identity="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"toe-dev"'; then
    identity="toe-dev"
fi
codesign --force --sign "$identity" --identifier com.clifmeister.toe "$app" >/dev/null 2>&1
if [ "$identity" = "-" ]; then echo "signed ad-hoc"; else echo "signed with $identity"; fi

echo "built $app"
