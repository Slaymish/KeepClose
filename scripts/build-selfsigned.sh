#!/bin/bash
# Build signed-by-this-Mac Keep Close release archives without notarization.
#
# This is the offline/self-signed path for a personal machine. It signs with a
# certificate that exists in this keychain (Developer ID if present, otherwise
# Apple Development) and produces the same file names as the Release workflow:
# KeepClose-macOS.zip, keepclose-cli-macOS.zip and SHA256SUMS.
#
# Not notarized: other Macs will refuse the first launch until the user approves it
# in System Settings -> Privacy & Security, or clears the quarantine flag. Prefer the
# tagged Release workflow whenever Developer ID credentials are available.
#
# Usage: scripts/build-selfsigned.sh [VERSION] [--publish]
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-$(sed -n "s/.*MARKETING_VERSION: '\([0-9.]*\)'.*/\1/p" project.yml)}"
build="$(sed -n 's/.*CURRENT_PROJECT_VERSION: \([0-9]*\).*/\1/p' project.yml)"
publish=false
[[ "${2:-}" == "--publish" ]] && publish=true
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid version/build in project.yml' >&2; exit 1; }

# Two certificates can share a common name, so identify by SHA-1. Prefer Developer ID;
# otherwise use the first valid Apple Development certificate.
developer_id=''; apple_development=''; local_signing=''
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]{40})[[:space:]]+\"(.*)\" ]] || continue
  hash="${BASH_REMATCH[1]}"
  name="${BASH_REMATCH[2]}"
  case "$name" in
    "Developer ID Application:"*) [[ -z "$developer_id" ]] && developer_id="$hash" ;;
    "Keep Close Local Signing"*) [[ -z "$local_signing" ]] && local_signing="$hash" ;;
    "Apple Development:"*) [[ -z "$apple_development" ]] && apple_development="$hash" ;;
  esac
done < <(security find-identity -v -p codesigning 2>/dev/null)
identity="${KEEPCLOSE_SIGNING_IDENTITY:-${developer_id:-${local_signing:-$apple_development}}}"
[[ -n "$identity" ]] || { echo 'No usable codesigning identity in the keychain.' >&2; exit 1; }

dist='.build-release/dist'
mkdir -p "$dist"

# SwiftPM's manifest cache lives under the user Library; create it if a sandboxed shell
# has never been able to. This changes nothing outside the build's own cache.
spm_cache="$HOME/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading"
if [[ ! -w "$(dirname "$(dirname "$spm_cache")")" && ! -d "$spm_cache" ]]; then
  mkdir -p "$spm_cache" 2>/dev/null || true
fi

identity_name=$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$identity" | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
[[ -n "$identity_name" ]] || identity_name="$identity"
echo "Building Keep Close $version ($build) signed as: ${identity_name:-$identity}"
xcodegen generate >/dev/null
# OTHER_SWIFT_FLAGS lets the macro plugin server run on hosts that cannot nest a sandbox.
xcodebuild -project SocialManager.xcodeproj -scheme SocialManager -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build-release/xcode \
  CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox' build >/dev/null

# Stage under a name without spaces: archiving a bundle whose parent ends in
# "Keep Close.app" misbehaves on some filesystems, producing the wrong contents.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
app="$staging/KeepClose.app"
cp -R .build-release/xcode/Build/Products/Release/SocialManager.app "$app"
# A self-signed build has no notarization ticket, so skip the network timestamp, and
# only Apple-issued certificates support the hardened runtime flag.
codesign_options='none'
[[ "$identity" == "$developer_id" || "$identity" == "$apple_development" ]] && codesign_options='runtime'
KEEPCLOSE_CODESIGN_TIMESTAMP=none KEEPCLOSE_CODESIGN_OPTIONS="$codesign_options" \
  python3 scripts/sign-bundle.py "$app" "$identity"

for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --scratch-path ".build-release/cli-$arch" --product keepclose --disable-sandbox >/dev/null
  bin_dir=$(swift build -c release --arch "$arch" --scratch-path ".build-release/cli-$arch" --show-bin-path --disable-sandbox)
  cp "$bin_dir/keepclose" ".build-release/keepclose-$arch"
done
lipo -create .build-release/keepclose-arm64 .build-release/keepclose-x86_64 -output "$dist/keepclose"
codesign --force --sign "$identity" --options runtime --timestamp=none "$dist/keepclose"

# Each archive is built in the staging directory and checked, so a failure can never
# leave a correctly named archive with the wrong contents.
rm -f "$dist/KeepClose-macOS.zip" "$dist/keepclose-cli-macOS.zip"

app_zip="$staging/KeepClose-macOS.zip"
python3 scripts/make-archive.py "$app" "$app_zip" --expect Contents/MacOS/SocialManager
mv -f "$app_zip" "$dist/KeepClose-macOS.zip"

cli_zip="$staging/keepclose-cli-macOS.zip"
python3 scripts/make-archive.py "$dist/keepclose" "$cli_zip" --expect keepclose
mv -f "$cli_zip" "$dist/keepclose-cli-macOS.zip"

python3 scripts/verify-release-archives.py "$dist" "$version" "$build"

# The existing app-specific update key authenticates archives and feed, independently of Apple signing.
signer="${SPARKLE_BIN:-.build-release/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin}/sign_update"
[[ -x "$signer" ]] || { echo 'Sparkle release tools were not resolved by the app build.' >&2; exit 1; }
key_arguments=(--account KeepClose)
[[ -n "${SPARKLE_KEY_FILE:-}" ]] && key_arguments=(--ed-key-file "$SPARKLE_KEY_FILE")
signature=$("$signer" "${key_arguments[@]}" -p "$dist/KeepClose-macOS.zip")
public=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")
scripts/native-library-tool verify-update.swift "$dist/KeepClose-macOS.zip" "$public" "$signature"
python3 scripts/generate-appcast.py --version "$version" --build "$build" --archive "$dist/KeepClose-macOS.zip" \
  --signature "$signature" --output "$dist/appcast.xml"
"$signer" "${key_arguments[@]}" "$dist/appcast.xml"
"$signer" "${key_arguments[@]}" --verify "$dist/appcast.xml"
( cd "$dist" && shasum -a 256 KeepClose-macOS.zip keepclose-cli-macOS.zip appcast.xml > SHA256SUMS )


echo
echo "Signed with: ${identity_name:-$identity}"
codesign --verify --deep --strict --verbose=1 "$app" 2>&1 | sed 's#^#  #'
codesign -dv "$dist/keepclose" 2>&1 | sed -n 's/^Authority=/  CLI authority: /p'
echo
cat "$dist/SHA256SUMS" | sed 's/^/  /'
echo
echo "Artifacts in $dist (not notarized)."

if $publish; then
  tag="v$version"
  git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null && { echo "Tag $tag already exists; refusing to reuse it." >&2; exit 1; }
  [[ -z "$(git status --porcelain)" ]] || { echo 'Working tree is not clean.' >&2; exit 1; }
  python3 scripts/release.py verify "$version" >/dev/null
  notes=$(python3 scripts/release.py notes "$version")
  git tag -a "$tag" -m "Keep Close $version (self-signed, not notarized)"
  git push origin "$tag"
  gh release create "$tag" --repo slaymish/KeepClose --title "Keep Close $version" --notes "$notes

---

**Self-signed build, not notarized.** This release was signed on the maintainer's Mac without a
Developer ID certificate. On another Mac, macOS will block the first launch:

1. Try to open the app, then go to **System Settings -> Privacy & Security** and choose **Open Anyway**.
   For the CLI: \`xattr -d com.apple.quarantine keepclose\`.

The update archive and feed are signed with the existing Sparkle key. This authenticates updates,
but does not provide Apple notarization or remove first-launch approval requirements." \
    "$dist/KeepClose-macOS.zip" "$dist/keepclose-cli-macOS.zip" "$dist/appcast.xml" "$dist/SHA256SUMS"
  echo "Published $tag."
fi
