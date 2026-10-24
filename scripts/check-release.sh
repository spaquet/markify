#!/bin/bash
# Checks a published release the way installed copies will see it: all eight assets are attached, each
# architecture's live appcast names this version and build, and its update archive verifies against
# SUPublicEDKey in Info.plist, has a valid code signature, holds the right build and architecture, and
# bundles the CLI.
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
EXPECTED="appcast-intel.xml appcast.xml markify-as-update.zip markify-as.dmg markify-as.dmg.sha256 markify-intel-update.zip markify-intel.dmg markify-intel.dmg.sha256 "
[ "$ASSETS" = "$EXPECTED" ] || { echo "Assets on $TAG: $ASSETS(expected $EXPECTED)" >&2; exit 1; }
echo "✓ $TAG has all eight assets"

LATEST=$(gh release view --json tagName -q .tagName)
[ "$LATEST" = "$TAG" ] || { echo "Latest release is $LATEST, not $TAG" >&2; exit 1; }

# Each feed is checked against the architecture its archive was built for.
check_feed() {
    local FEED=$1 ARCH=$2 NAME=$3
    local DIR="$WORK/$NAME"
    mkdir -p "$DIR"
    curl -fsSL "https://github.com/$REPO/releases/latest/download/$FEED" -o "$DIR/appcast.xml"
    xmllint --noout "$DIR/appcast.xml"
    local FEED_VERSION FEED_BUILD URL SIGNATURE LENGTH
    FEED_VERSION=$(xmllint --xpath 'string(//*[local-name()="shortVersionString"])' "$DIR/appcast.xml")
    FEED_BUILD=$(xmllint --xpath 'string(//*[local-name()="version"])' "$DIR/appcast.xml")
    URL=$(xmllint --xpath 'string(//enclosure/@url)' "$DIR/appcast.xml")
    SIGNATURE=$(xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' "$DIR/appcast.xml")
    LENGTH=$(xmllint --xpath 'string(//enclosure/@length)' "$DIR/appcast.xml")
    [ "$FEED_VERSION" = "$VERSION" ] || { echo "$FEED names $FEED_VERSION, not $VERSION" >&2; exit 1; }
    [ -z "$BUILD" ] || [ "$FEED_BUILD" = "$BUILD" ] || { echo "$FEED build is $FEED_BUILD, not $BUILD" >&2; exit 1; }
    echo "✓ Live $FEED names $FEED_VERSION ($FEED_BUILD)"

    curl -fsSL "$URL" -o "$DIR/update.zip"
    [ "$(stat -f%z "$DIR/update.zip")" = "$LENGTH" ] || { echo "Archive length doesn't match $FEED" >&2; exit 1; }
    swift scripts/verify-update-signature.swift \
        "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Markify/Info.plist)" "$SIGNATURE" "$DIR/update.zip"
    ditto -x -k "$DIR/update.zip" "$DIR/app"
    codesign --verify --deep --strict "$DIR/app/Markify.app"
    local APP_BUILD ARCHS
    APP_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DIR/app/Markify.app/Contents/Info.plist")
    [ "$APP_BUILD" = "$FEED_BUILD" ] || { echo "The $NAME archive's app is build $APP_BUILD, $FEED says $FEED_BUILD" >&2; exit 1; }
    ARCHS=$(lipo -archs "$DIR/app/Markify.app/Contents/MacOS/Markify")
    [ "$ARCHS" = "$ARCH" ] || { echo "The $NAME archive is $ARCHS, not $ARCH" >&2; exit 1; }
    echo "✓ $NAME update archive: valid code signature, build $APP_BUILD, $ARCHS"
    otool -L "$DIR/app/Markify.app/Contents/MacOS/Markify" | grep -q 'SwiftUI.framework' \
        || { echo "Contents/MacOS/Markify is not the app (the CLI replaced it?)" >&2; exit 1; }
    "$DIR/app/Markify.app/Contents/Helpers/markify" --help | grep -q 'markify view' \
        || { echo "The bundled CLI is missing from Contents/Helpers" >&2; exit 1; }
    echo "✓ $NAME update archive: app executable and bundled CLI"
}

check_feed appcast.xml arm64 as
check_feed appcast-intel.xml x86_64 intel
