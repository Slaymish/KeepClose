#!/bin/bash
# Create a local self-signed code-signing identity for Keep Close development builds.
#
# The keychain's Apple Development certificate is revoked, and a Developer ID
# certificate needs Apple Developer Program membership. This makes a certificate
# that belongs only to this Mac: fine for local builds, not notarizable, and other
# Macs will require explicit approval before launching the app.
#
# Idempotent: re-running reuses the existing identity.
# Usage: scripts/create-selfsigned-identity.sh
set -euo pipefail
cd "$(dirname "$0")/.."

common_name="${KEEPCLOSE_SELFSIGNED_CN:-Keep Close Local Signing}"
keychain="$HOME/Library/Keychains/login.keychain-db"
key_dir="$HOME/.keepclose-release"
work_dir="$key_dir/selfsigned"
mkdir -p "$work_dir"
chmod 700 "$key_dir" "$work_dir"

if security find-certificate -c "$common_name" "$keychain" >/dev/null 2>&1; then
  echo "Already present: $common_name"
  security find-certificate -c "$common_name" -Z "$keychain" 2>/dev/null | sed -n 's/^SHA-1 hash: /  SHA-1: /p'
  exit 0
fi

cat > "$work_dir/codesign.cnf" <<'CONF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Keep Close Local Signing
O = Keep Close local development
[ ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONF

serial=$(openssl rand -hex 8)
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -config "$work_dir/codesign.cnf" \
  -set_serial "0x$serial" \
  -keyout "$work_dir/key.pem" -out "$work_dir/cert.pem" >/dev/null 2>&1
chmod 600 "$work_dir/key.pem"

p12="$work_dir/identity.p12"
p12_password=$(openssl rand -hex 16)
# macOS security(1) cannot read OpenSSL 3's default PKCS#12 MAC/KDF combination ("MAC
# verification failed"), so export with the SHA-1/3DES parameters it does understand.
openssl pkcs12 -export -out "$p12" -inkey "$work_dir/key.pem" -in "$work_dir/cert.pem" \
  -name "$common_name" -passout "pass:$p12_password" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null
chmod 600 "$p12"

security unlock-keychain -p "$(security default-keychain | sed 's/.*"\(.*\)".*/\1/')" "$keychain" >/dev/null 2>&1 || true
security import "$p12" -k "$keychain" -P "$p12_password" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
printf '%s' "$p12_password" > "$work_dir/p12-password.txt"
chmod 600 "$work_dir/p12-password.txt"

# A self-signed certificate is untrusted until trust settings say otherwise, and
# codesign ignores untrusted identities. Trust it for code signing only, for this user.
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work_dir/cert.pem" \
  || echo "warning: could not add trust settings; approve the certificate in Keychain Access if signing fails." >&2

echo "Created local self-signed identity: $common_name"
security find-identity -v -p codesigning "$keychain" 2>/dev/null | grep -F "$common_name" || {
  echo "The new identity is not usable for codesigning. Open Keychain Access, find \"$common_name\"," >&2
  echo "open it, expand Trust and set Code Signing to Always Trust." >&2
  exit 1
}
echo
echo "Key material is in $work_dir (self-signed; back up the .p12 and its password if you want it later)."
