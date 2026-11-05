#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
DERIVED="${MOTONAV_DERIVED_DATA:-$(mktemp -d /tmp/MotoNavRelease.XXXXXX)}"
OUT="$ROOT/output/ios"
mkdir -p "$OUT"
# CI 用 run_number 覆写 build 号，每次打包都不同；本地不传就沿用工程里的 CURRENT_PROJECT_VERSION
BUILD_ARG=""
if [[ -n "${MOTONAV_BUILD_NUMBER:-}" ]]; then
  BUILD_ARG="CURRENT_PROJECT_VERSION=${MOTONAV_BUILD_NUMBER}"
fi
xcodebuild -workspace "$ROOT/ios/MotoNav.xcworkspace" -scheme MotoNav \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= $BUILD_ARG build
APP="$DERIVED/Build/Products/Release-iphoneos/MotoNav.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist")
EXT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/PlugIns/MotoNavShare.appex/Info.plist")
EXT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/PlugIns/MotoNavShare.appex/Info.plist")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD" =~ ^[0-9]+$ || "$VERSION" != "$EXT_VERSION" || "$BUILD" != "$EXT_BUILD" ]]; then
  echo '应用与分享扩展版本不一致，或版本格式不正确。' >&2
  exit 1
fi
STAGE=$(mktemp -d /tmp/MotoNavPayload.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/MotoNav.app"
find "$STAGE" -name _CodeSignature -type d -prune -exec rm -rf {} +
find "$STAGE" -name embedded.mobileprovision -delete
xcrun strip -S "$STAGE/Payload/MotoNav.app/MotoNav"
xcrun strip -S "$STAGE/Payload/MotoNav.app/PlugIns/MotoNavShare.appex/MotoNavShare"
IPA="$OUT/MotoNav-$VERSION-build$BUILD.ipa"
rm -f "$IPA"
(cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
(cd "$OUT" && shasum -a 256 "$(basename "$IPA")" > SHA256SUMS.txt)
echo "版本 $VERSION · Build $BUILD"
echo "$IPA"
