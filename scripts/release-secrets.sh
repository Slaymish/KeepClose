#!/bin/bash
# Load the Apple release credentials for Keep Close from wherever they live on this
# Mac, then optionally tag the prepared release.
#
# The user runs one function call. Every value is validated before it reaches GitHub,
# and secret values are never echoed.
#
#   setup   install this helper and create the private credential directory
#   check   report which credential pieces are present or missing
#   load    validate locally, then set the six GitHub secrets
#   tag     tag the prepared commit and watch the Release workflow
#
# Usage: scripts/release-secrets.sh <setup|check|load|tag> [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

repo='slaymish/KeepClose'
key_dir="$HOME/.keepclose-release"
fn_name='kc_release_secrets'
zshrc="$HOME/.zshrc"
version='0.1.0'
marker_begin='# keepclose release helper'
marker_end='# end keepclose release helper'
action="${1:-check}"
dry_run=false
[[ "${2:-}" == "--dry-run" ]] && dry_run=true

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

identity_of() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1
}

helper_body() {
  cat <<'EOS'
kc_release_secrets() {
  local root="$HOME/Developer/SocialManager"
  [[ -d "$root/scripts" ]] || root="$(pwd)"
  ( cd "$root" && exec scripts/release-secrets.sh load )
}
EOS
}

case "$action" in
  setup)
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    if ! grep -qF "$marker_begin" "$zshrc" 2>/dev/null; then
      { printf '\n%s\n' "$marker_begin"
        helper_body
        printf '%s\n' "$marker_end"
      } >> "$zshrc"
      note "Added the $fn_name helper to $zshrc."
    else
      note "The $fn_name helper is already in $zshrc."
    fi
    printf 'Put the App Store Connect API key here:\n'
    printf '  %s/AuthKey.p8            the downloaded .p8, complete\n' "$key_dir"
    printf '  %s/notary-key-id.txt     the key ID, e.g. 2X9R4HXF34\n' "$key_dir"
    printf '  %s/notary-issuer-id.txt  the issuer UUID\n' "$key_dir"
    printf 'Then run:  source ~/.zshrc && kc_release_secrets\n'
    ;;

  check)
    note "Repository: $repo"
    note "Working tree: $(cd "$root" && git rev-parse --short HEAD) on $(git -C "$root" branch --show-current)"
    note "Prepared release: $version (build $(sed -n 's/.*CURRENT_PROJECT_VERSION: \([0-9]*\).*/\1/p' project.yml))"
    existing_tags=$(git -C "$root" tag -l | tr '\n' ' ')
    note "Existing tags: ${existing_tags:-none}"
    note "Version tag present: $(git -C "$root" tag -l "v$version" | wc -l | tr -d ' ')"
    note ''
    note 'Credentials:'
    local_identity=$(identity_of || true)
    if [[ -n "$local_identity" ]]; then note "  [ok]      Keychain identity: $local_identity"
    else note "  [MISSING] Developer ID Application certificate in the keychain"; fi
    for item in "AuthKey.p8:App Store Connect .p8 key" \
                "notary-key-id.txt:API key ID" \
                "notary-issuer-id.txt:API issuer ID"; do
      file="${item%%:*}"; label="${item#*:}"
      if [[ -s "$key_dir/$file" ]]; then note "  [ok]      $label ($key_dir/$file)"
      else note "  [MISSING] $label ($key_dir/$file)"; fi
    done
    if [[ -s "$key_dir/developer-id.p12" ]]; then note "  [ok]      Exported .p12 ($key_dir/developer-id.p12)"
    else note "  [pending] Exported .p12 (will be exported from the keychain when you load)"; fi
    note ''
    note 'GitHub secrets (names only):'
    gh secret list --repo "$repo" 2>&1 | sed 's/\t.*/ (set)/' | sed 's/^/  /'
    ;;

  load)
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    local_identity=$(identity_of || true)

    secret_files=()
    for name in "$key_dir/notary-key-id.txt" "$key_dir/notary-issuer-id.txt" "$key_dir/AuthKey.p8"; do
      [[ -s "$name" ]] && secret_files+=("$name")
    done
    [[ -n "$local_identity" ]] || fail "no Developer ID Application identity in the keychain.

Apple Development cannot publish. Create a Developer ID Application certificate, which needs
Apple Developer Program membership:
  Xcode -> Settings -> Accounts -> select your team -> Manage Certificates -> + -> Developer ID Application
or create it at https://developer.apple.com/account/resources/certificates and download it.
Then run:  kc_release_secrets"

    (( ${#secret_files[@]} == 3 )) || fail "put the App Store Connect API key here first:
  $key_dir/AuthKey.p8             the downloaded .p8, complete
  $key_dir/notary-key-id.txt      the key ID, e.g. 2X9R4HXF34
  $key_dir/notary-issuer-id.txt   the issuer UUID
Protect them with:  chmod 600 $key_dir/*
Then run:  kc_release_secrets"

    p12="$key_dir/developer-id.p12"
    if [[ ! -s "$p12" ]]; then
      p12_password=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
      if ! security export -t identities -f pkcs12 -P "$p12_password" \
             -k "$HOME/Library/Keychains/login.keychain-db" "$p12" >/dev/null 2>&1 \
         && ! security export -t identities -f pkcs12 -P "$p12_password" "$p12" >/dev/null 2>&1; then
        fail "could not export identities from the keychain.
Export the Developer ID Application certificate and its key by hand:
  Keychain Access -> My Certificates -> select both the certificate and its private key
  -> right click -> Export Items -> .p12
Save it as $p12, put its password in $key_dir/p12-password.txt, then run:  kc_release_secrets"
      fi
      printf '%s' "$p12_password" > "$key_dir/p12-password.txt"
      chmod 600 "$key_dir/p12-password.txt"
      note "Exported identities to $p12 with a generated password."
    fi

    case "$(base64 -i "$p12" | tr -d '\n' | head -c 4)" in
      MII*) ;;
      *) fail "$p12 does not look like a PKCS#12 archive. Re-export it from Keychain Access." ;;
    esac
    case "$(head -c 80 "$key_dir/AuthKey.p8")" in
      *"PRIVATE KEY"*) ;;
      *) fail "$key_dir/AuthKey.p8 does not look like a .p8 private key." ;;
    esac
    case "$(tr -d '\n' < "$key_dir/notary-issuer-id.txt")" in
      [0-9a-fA-F]*-*-*-*-*) ;;
      *) fail "$key_dir/notary-issuer-id.txt should be the issuer UUID." ;;
    esac
    [[ -s "$key_dir/p12-password.txt" ]] || fail "missing $key_dir/p12-password.txt (the password for $p12)"

    note "Publisher: $local_identity"
    note "Secrets to write to $repo:"
    for secret in APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_SIGNING_IDENTITY \
                  APPLE_API_KEY_ID APPLE_API_ISSUER_ID APPLE_API_PRIVATE_KEY; do
      note "  $secret"
    done
    if $dry_run; then
      note '--dry-run: all checks passed; nothing was sent to GitHub.'
      exit 0
    fi

    printf '%s' "$local_identity" > "$key_dir/identity.txt"
    base64 -i "$p12" | tr -d '\n' | gh secret set APPLE_CERTIFICATE_P12_BASE64 --repo "$repo"
    gh secret set APPLE_CERTIFICATE_PASSWORD --repo "$repo" < "$key_dir/p12-password.txt"
    gh secret set APPLE_SIGNING_IDENTITY --repo "$repo" < "$key_dir/identity.txt"
    gh secret set APPLE_API_KEY_ID --repo "$repo" < "$key_dir/notary-key-id.txt"
    gh secret set APPLE_API_ISSUER_ID --repo "$repo" < "$key_dir/notary-issuer-id.txt"
    gh secret set APPLE_API_PRIVATE_KEY --repo "$repo" < "$key_dir/AuthKey.p8"
    note ''
    gh secret list --repo "$repo"
    note ''
    note "Keep the .p12 and its password somewhere safe offline (they are in $key_dir)."
    note 'Next:  kc_release_secrets tag   — or ask the agent to tag v'"$version"'.'
    ;;

  tag)
    git -C "$root" rev-parse --verify --quiet "refs/tags/v$version" >/dev/null && fail "tag v$version already exists. Never reuse or force a published tag."
    [[ -z "$(git -C "$root" status --porcelain)" ]] || fail "working tree is not clean. Commit or stash first."
    python3 "$root/scripts/release.py" verify "$version"
    git -C "$root" tag -a "v$version" -m "Keep Close $version"
    git -C "$root" push origin "v$version"
    note "Pushed v$version. Watching the Release workflow…"
    gh run watch --repo "$repo" "$(gh run list --repo "$repo" --workflow Release --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
    ;;

  *)
    fail 'usage: scripts/release-secrets.sh <setup|check|load|tag> [--dry-run]'
    ;;
esac
