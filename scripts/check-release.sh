#!/bin/bash
# Checks a published release the way installed copies will see it: all six
# assets are attached, the live appcast (releases/latest/download/appcast.xml)
# names this version and build, and the update archive's EdDSA signature
# verifies against SUPublicEDKey in Info.plist.
#
# Usage: scripts/check-release.sh v1.61 [build]
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?usage: check-release.sh <tag> [build]}
VERSION=${TAG#v}
BUILD=${2:-}
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ASSETS=$(gh release view "$TAG" --json assets -q '.assets[].name' | sort | tr '\n' ' ')
EXPECTED="appcast.xml markify-as.dmg markify-as.dmg.sha256 markify-intel.dmg markify-intel.dmg.sha256 markify-update.zip "
[ "$ASSETS" = "$EXPECTED" ] || { echo "Assets on $TAG: $ASSETS(expected $EXPECTED)" >&2; exit 1; }
echo "✓ $TAG has all six assets"

LATEST=$(gh release view --json tagName -q .tagName)
[ "$LATEST" = "$TAG" ] || { echo "Latest release is $LATEST, not $TAG" >&2; exit 1; }

curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" -o "$WORK/appcast.xml"
xmllint --noout "$WORK/appcast.xml"
FEED_VERSION=$(xmllint --xpath 'string(//*[local-name()="shortVersionString"])' "$WORK/appcast.xml")
FEED_BUILD=$(xmllint --xpath 'string(//*[local-name()="version"])' "$WORK/appcast.xml")
URL=$(xmllint --xpath 'string(//enclosure/@url)' "$WORK/appcast.xml")
SIGNATURE=$(xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' "$WORK/appcast.xml")
LENGTH=$(xmllint --xpath 'string(//enclosure/@length)' "$WORK/appcast.xml")
[ "$FEED_VERSION" = "$VERSION" ] || { echo "Feed names $FEED_VERSION, not $VERSION" >&2; exit 1; }
[ -z "$BUILD" ] || [ "$FEED_BUILD" = "$BUILD" ] || { echo "Feed build is $FEED_BUILD, not $BUILD" >&2; exit 1; }
echo "✓ Live appcast names $FEED_VERSION ($FEED_BUILD)"

curl -fsSL "$URL" -o "$WORK/update.zip"
[ "$(stat -f%z "$WORK/update.zip")" = "$LENGTH" ] || { echo "Archive length doesn't match the appcast" >&2; exit 1; }
swift scripts/verify-update-signature.swift \
    "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Markify/Info.plist)" "$SIGNATURE" "$WORK/update.zip"
ditto -x -k "$WORK/update.zip" "$WORK/app"
codesign --verify --deep --strict "$WORK/app/Markify.app"
APP_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$WORK/app/Markify.app/Contents/Info.plist")
[ "$APP_BUILD" = "$FEED_BUILD" ] || { echo "The archive's app is build $APP_BUILD, the feed says $FEED_BUILD" >&2; exit 1; }
echo "✓ Update archive: valid code signature, build $APP_BUILD, $(lipo -archs "$WORK/app/Markify.app/Contents/MacOS/Markify")"
otool -L "$WORK/app/Markify.app/Contents/MacOS/Markify" | grep -q 'SwiftUI.framework' \
    || { echo "Contents/MacOS/Markify is not the app (the CLI replaced it?)" >&2; exit 1; }
"$WORK/app/Markify.app/Contents/Helpers/markify" --help | grep -q 'markify view' \
    || { echo "The bundled CLI is missing from Contents/Helpers" >&2; exit 1; }
echo "✓ Update archive: app executable and bundled CLI"
