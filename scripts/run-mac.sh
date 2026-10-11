#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
identity="${KEEPCLOSE_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning | awk '/Apple Development/ && !/REVOKED/ {print $2; exit}')
fi
if [[ -z "$identity" ]]; then
  print -u2 'No valid Apple Development identity found. Choose a signing team in Xcode and Run.'
  exit 1
fi
xcodegen generate
xcodebuild -project SocialManager.xcodeproj -scheme SocialManager -destination 'platform=macOS' -derivedDataPath .build-xcode CODE_SIGNING_ALLOWED=NO build
app_path="$project_root/.build-xcode/Build/Products/Debug/SocialManager.app"
python3 scripts/sign-bundle.py "$app_path" "$identity"
# Build the CLI alongside the app. The original Mac data stays in place.
swift build --product keepclose
open "$app_path"
