#!/bin/bash
# One-time setup for Sparkle updates: creates the EdDSA key pair in the login
# keychain (or reuses the one already there), writes the public key to
# Markify/Info.plist, and stores the private key as the SPARKLE_PRIVATE_KEY
# repository secret. Run it again to repair a secret that doesn't match.
set -euo pipefail
cd "$(dirname "$0")/.."

SPM=.build/spm
echo "Resolving packages for Sparkle's tools…"
xcodebuild -resolvePackageDependencies -project Markify.xcodeproj -scheme Markify \
    -clonedSourcePackagesDirPath "$SPM" >/dev/null
BIN="$SPM/artifacts/sparkle/Sparkle/bin"

# Creates a key only when the keychain has none; the keychain may ask for access.
"$BIN/generate_keys" >/dev/null
PUBLIC_KEY=$("$BIN/generate_keys" -p)

perl -0pi -e "s|(<key>SUPublicEDKey</key>\s*<string>)[^<]*|\${1}$PUBLIC_KEY|" Markify/Info.plist
echo "SUPublicEDKey in Markify/Info.plist: $PUBLIC_KEY"

KEY_DIR=$(mktemp -d)
trap 'rm -rf "$KEY_DIR"' EXIT
"$BIN/generate_keys" -x "$KEY_DIR/private.key" >/dev/null
gh secret set SPARKLE_PRIVATE_KEY < "$KEY_DIR/private.key"
echo "Stored the private key as the SPARKLE_PRIVATE_KEY secret."
echo "Back up the key (generate_keys -x <file>) somewhere safe; installed copies only accept updates signed with it."
