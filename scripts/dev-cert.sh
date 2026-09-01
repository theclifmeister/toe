#!/usr/bin/env bash
# Creates a self-signed code-signing certificate named "toe-dev" in the login keychain.
#
# Why: macOS keys Accessibility grants to an app's code signature. An ad-hoc signature changes
# on every build, so macOS re-asks for permission after each rebuild. A stable signing identity
# — even a self-signed one — makes the grant stick.
#
# Trusting the certificate prompts once for your login password. Run this once; scripts/bundle.sh
# picks the identity up automatically and falls back to ad-hoc signing if it is absent.
set -euo pipefail

name="toe-dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$name\""; then
    echo "$name already exists"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 -nodes \
    -subj "/CN=$name/O=toe/C=US" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

# Apple's Security framework cannot read OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -out "$tmp/$name.p12" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -passout pass:"$name" -name "$name" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null

security import "$tmp/$name.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$name" -T /usr/bin/codesign -A
echo "granting trust — macOS will ask for your login password"
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$tmp/cert.pem"

security find-identity -v -p codesigning | grep "\"$name\""
