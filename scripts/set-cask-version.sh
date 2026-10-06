#!/bin/bash
# Points the Homebrew cask (Casks/markify.rb) at a published release: its version and the SHA-256 of
# both DMGs, taken from the release's .sha256 files after checking them against the downloaded DMGs.
# Then lints the cask and, with --audit, audits both architectures through a temporary local tap
# (it reads the committed cask, so commit first). See HOMEBREW.md.
#
# Usage: scripts/set-cask-version.sh 2.2.0
#        scripts/set-cask-version.sh --audit
set -euo pipefail
cd "$(dirname "$0")/.."
CASK=Casks/markify.rb

if [ "${1:-}" = "--audit" ]; then
    TAP=markify-release/check
    brew untap "$TAP" >/dev/null 2>&1 || true
    brew tap "$TAP" "file://$PWD" >/dev/null
    trap 'brew untap "$TAP" >/dev/null 2>&1 || true' EXIT
    brew audit --cask --strict --online --arch all "$TAP/markify"
    echo "Cask audit passed for $(grep -m1 -o 'version "[^"]*"' "$CASK")."
    exit 0
fi

VERSION=${1:?usage: set-cask-version.sh <version> | --audit}
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Not a version: $VERSION" >&2; exit 1; }

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
gh release download "v$VERSION" --pattern 'markify-*.dmg*' -D "$DIR"
(cd "$DIR" && shasum -a 256 -c markify-as.dmg.sha256 && shasum -a 256 -c markify-intel.dmg.sha256)
ARM=$(awk '{print $1}' "$DIR/markify-as.dmg.sha256")
INTEL=$(awk '{print $1}' "$DIR/markify-intel.dmg.sha256")

perl -pi -e "s{^(\s*version )\"[^\"]*\"}{\$1\"$VERSION\"};
             s{(sha256 arm:\s*)\"[0-9a-f]{64}\"}{\$1\"$ARM\"};
             s{(intel:\s*)\"[0-9a-f]{64}\"}{\$1\"$INTEL\"}" "$CASK"

grep -q "version \"$VERSION\"" "$CASK" && grep -q "$ARM" "$CASK" && grep -q "$INTEL" "$CASK" \
    || { echo "Could not update $CASK; check its version and sha256 stanzas." >&2; exit 1; }
brew style "$CASK"
echo "$CASK now names Markify $VERSION (arm $ARM, intel $INTEL)."
