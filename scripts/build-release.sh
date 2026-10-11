#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${KEEPCLOSE_SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
: "${NOTARY_KEY_FILE:?Set the App Store Connect API private key file}"
: "${NOTARY_KEY_ID:?Set the App Store Connect API key ID}"
: "${NOTARY_ISSUER_ID:?Set the App Store Connect issuer ID}"
version="${1:?Usage: scripts/build-release.sh VERSION BUILD_NUMBER}"
build="${2:?Supply an increasing integer build number}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid release version/build number' >&2; exit 1; }
[[ "$KEEPCLOSE_SIGNING_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Distribution requires Developer ID Application, not Apple Development.' >&2; exit 1; }
mkdir -p .build-release/dist
xcodegen generate
xcodebuild -project SocialManager.xcodeproj -scheme SocialManager -configuration Release -destination 'platform=macOS' -derivedDataPath .build-release/xcode CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
app='.build-release/dist/Keep Close.app'
rm -rf "$app"
cp -R .build-release/xcode/Build/Products/Release/SocialManager.app "$app"
python3 scripts/sign-bundle.py "$app" "$KEEPCLOSE_SIGNING_IDENTITY"
ditto -c -k --sequesterRsrc --keepParent "$app" .build-release/notarize-app.zip
xcrun notarytool submit .build-release/notarize-app.zip --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait --output-format json > .build-release/app-notarization.json
python3 -c 'import json; assert json.load(open(".build-release/app-notarization.json"))["status"] == "Accepted", "App notarization was rejected"'
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" .build-release/dist/KeepClose-macOS.zip
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --scratch-path ".build-release/cli-$arch" --product keepclose
  bin_dir=$(swift build -c release --arch "$arch" --scratch-path ".build-release/cli-$arch" --show-bin-path)
  cp "$bin_dir/keepclose" ".build-release/keepclose-$arch"
done
lipo -create .build-release/keepclose-arm64 .build-release/keepclose-x86_64 -output .build-release/dist/keepclose
codesign --force --sign "$KEEPCLOSE_SIGNING_IDENTITY" --options runtime --timestamp .build-release/dist/keepclose
ditto -c -k --keepParent .build-release/dist/keepclose .build-release/dist/keepclose-macOS.zip
xcrun notarytool submit .build-release/dist/keepclose-macOS.zip --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait --output-format json > .build-release/cli-notarization.json
python3 -c 'import json; assert json.load(open(".build-release/cli-notarization.json"))["status"] == "Accepted", "CLI notarization was rejected"'
# CLI cannot staple a ticket; Gatekeeper can retrieve its notarization ticket online.
