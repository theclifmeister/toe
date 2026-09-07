#!/usr/bin/env bash
# Assembles Toe.app from the release binary and signs it.
#
# Three environment variables let CI and `make run` drive this without changing what the
# default build does:
#   TOE_SIGN_IDENTITY  signing identity to use, skipping the toe-dev/ad-hoc search
#   TOE_VERSION        version to stamp into the bundled Info.plist
#   TOE_DEV            build the development flavour — see below
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-release}"

# macOS keys an Accessibility grant to a bundle identifier *and* the code signature stored
# against it. The installed copy is signed with the Developer ID certificate and the local one
# with toe-dev, so sharing an identifier means each launch invalidates the other's grant and
# the permission has to be given again every time you swap between them. The development
# flavour is a separate application as far as macOS is concerned — its own identifier, its own
# grant, granted once — so the two can be swapped freely. They still cannot run at the same
# time, and do not: see `AppIdentity.takeOver`.
#
# No space in the bundle's file name, only in what it calls itself: `build/Toe Dev.app` would
# have to be quoted through every Makefile rule that touches it.
if [ -n "${TOE_DEV:-}" ]; then
    app="$root/build/ToeDev.app"
    bundle_id="com.clifmeister.toe.dev"
    bundle_name="Toe Dev"
else
    app="$root/build/Toe.app"
    bundle_id="com.clifmeister.toe"
    bundle_name="Toe"
fi

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

plist="$app/Contents/Info.plist"

# The committed Info.plist is the installed application's, so only the development flavour has
# anything to rewrite. `CFBundleName` is what the Accessibility list in System Settings shows,
# which is the one place the two copies have to be told apart by eye.
if [ -n "${TOE_DEV:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $bundle_name" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $bundle_name" "$plist"
fi

# Releases stamp the tag's version into the bundle. Left alone, the committed Info.plist
# version stands, so a local `make run` builds exactly what it always did.
if [ -n "${TOE_VERSION:-}" ]; then
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
# The signing identifier and not just the plist: TCC keys the grant to the identifier in the
# signature, so a dev bundle signed as the installed one would land back in its entry.
flags=(--force --sign "$identity" --identifier "$bundle_id")
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
