#!/usr/bin/env bash
# Assembles Toe.app from the release binary and signs it.
#
# Two environment variables let CI drive this without changing local behaviour:
#   TOE_SIGN_IDENTITY  signing identity to use, skipping the toe-dev/ad-hoc search
#   TOE_VERSION        version to stamp into the bundled Info.plist
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
# Info.plist's CFBundleIconFile names this. Copied before codesign below, so the signature
# covers it — otherwise `codesign --verify --deep --strict` in the release workflow fails.
cp "$root/Resources/Toe.icns" "$app/Contents/Resources/Toe.icns"
# The quick menu's typeface — Omarchy renders its own menu in this, and toe registers it at
# process scope rather than asking anyone to install it. Same placement as the icon above, and
# for the same reason: the signature has to cover it.
cp "$root/Resources/JetBrainsMonoNerdFont-Regular.ttf" "$app/Contents/Resources/"
cp "$root/Resources/JetBrainsMonoNerdFont-OFL.txt" "$app/Contents/Resources/"
printf 'APPL????' > "$app/Contents/PkgInfo"

# Releases stamp the tag's version into the bundle. Left alone, the committed Info.plist
# version stands, so a local `make run` builds exactly what it always did.
if [ -n "${TOE_VERSION:-}" ]; then
    plist="$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TOE_VERSION" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TOE_VERSION" "$plist"
    echo "stamped version $TOE_VERSION"
fi

# macOS keys Accessibility grants to the code signature. Prefer a real identity — the release
# certificate in CI, or the stable self-signed one from scripts/dev-cert.sh — so the grant
# survives an upgrade; fall back to ad-hoc signing, which changes on every build and makes
# macOS re-ask.
identity="-"
if [ -n "${TOE_SIGN_IDENTITY:-}" ]; then
    identity="$TOE_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"toe-dev"'; then
    identity="toe-dev"
fi
# Notarization requires the hardened runtime, and under it the SUPER+ENTER bindings lose
# their Apple Events access without Resources/toe.entitlements. --timestamp additionally needs
# the network and Apple's timestamp server — it is what keeps already-shipped builds valid
# after the certificate expires. Both are limited to the release path, so a local `make run`
# against toe-dev, and CI's ad-hoc fallback, sign exactly as they always did.
flags=(--force --sign "$identity" --identifier com.clifmeister.toe)
if [ -n "${TOE_SIGN_IDENTITY:-}" ]; then
    flags+=(--options runtime --timestamp --entitlements "$root/Resources/toe.entitlements")
fi

# Quiet on success — codesign is chatty — but show everything if it fails, so a CI signing
# problem reports itself instead of failing as a bare exit code.
if ! out="$(codesign "${flags[@]}" "$app" 2>&1)"; then
    echo "$out" >&2
    exit 1
fi
if [ "$identity" = "-" ]; then echo "signed ad-hoc"; else echo "signed with $identity"; fi

echo "built $app"
