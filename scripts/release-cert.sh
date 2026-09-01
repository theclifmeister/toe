#!/usr/bin/env bash
# Creates the "toe-release" self-signed code-signing certificate used by CI.
#
# Why a certificate at all, when it cannot be notarized: macOS keys Accessibility grants to an
# app's designated requirement. An ad-hoc signature puts the cdhash in that requirement, so it
# changes with every build and every `brew upgrade` would silently revoke the grant. Signing
# with a certificate — even a self-signed one nobody trusts — makes the requirement name the
# certificate instead, and the grant survives upgrades.
#
# ⚠️ Run this ONCE, ever. Regenerating the certificate changes the designated requirement and
# costs every existing user their Accessibility grant. Back the .p12 and its password up.
#
# usage: release-cert.sh [--out <path>] [--set-secrets <owner/repo>]
#
# With --set-secrets the three values are piped straight into `gh secret set` and never
# printed, so they stay out of your terminal scrollback. Without it they are printed for
# pasting into Settings → Secrets and variables → Actions.
set -euo pipefail

name="toe-release"
out="$PWD/$name.p12"
repo=""

while [ $# -gt 0 ]; do
    case "$1" in
        --out) out="$2"; shift 2 ;;
        --set-secrets) repo="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [ -e "$out" ]; then
    echo "$out already exists — refusing to overwrite an existing release certificate" >&2
    exit 1
fi

mkdir -p "$(dirname "$out")"
cert_password="$(openssl rand -base64 24)"
keychain_password="$(openssl rand -base64 24)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 -nodes \
    -subj "/CN=$name/O=toe/C=US" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

# Apple's Security framework cannot read OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -out "$out" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -passout pass:"$cert_password" -name "$name" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null
chmod 600 "$out"

# The passwords are needed again only if the secrets ever have to be re-created, so keep them
# next to the certificate rather than only in GitHub.
cat > "$out.passwords" <<EOF
SIGNING_CERT_PASSWORD=$cert_password
KEYCHAIN_PASSWORD=$keychain_password
EOF
chmod 600 "$out.passwords"

echo "wrote $out"
echo "wrote $out.passwords"
echo "SHA-256 fingerprint: $(openssl x509 -in "$tmp/cert.pem" -noout -fingerprint -sha256 | cut -d= -f2)"

if [ -n "$repo" ]; then
    base64 < "$out" | gh secret set SIGNING_CERT_P12_BASE64 --repo "$repo"
    printf '%s' "$cert_password" | gh secret set SIGNING_CERT_PASSWORD --repo "$repo"
    printf '%s' "$keychain_password" | gh secret set KEYCHAIN_PASSWORD --repo "$repo"
    echo "set SIGNING_CERT_P12_BASE64, SIGNING_CERT_PASSWORD and KEYCHAIN_PASSWORD on $repo"
else
    cat <<EOF

Add these repository secrets (Settings → Secrets and variables → Actions):

  SIGNING_CERT_P12_BASE64
$(base64 < "$out" | sed 's/^/    /')

  SIGNING_CERT_PASSWORD
    $cert_password

  KEYCHAIN_PASSWORD
    $keychain_password

EOF
fi

cat <<EOF

⚠️  Back up $out and $out.passwords somewhere durable — a password manager.
    Losing them means the next release must use a different certificate, and every user
    will have to grant Accessibility again.
EOF
