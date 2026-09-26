#!/bin/bash
# Points the website's version line and download section at a release:
# "Version X", "Markify X ·" and the releases/tag/vX links in docs/index.html.
# The download buttons use releases/latest/download/…, so they need no change.
#
# Usage: scripts/set-website-version.sh 1.61
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: set-website-version.sh <version>}
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Not a version: $VERSION" >&2; exit 1; }

perl -pi -e "s{releases/tag/v[0-9]+(?:\.[0-9]+){1,2}}{releases/tag/v$VERSION}g;
             s{Version [0-9]+(?:\.[0-9]+){1,2}}{Version $VERSION}g;
             s{Markify [0-9]+(?:\.[0-9]+){1,2} ·}{Markify $VERSION ·}g" docs/index.html

COUNT=$(grep -c -e "releases/tag/v$VERSION" docs/index.html)
if [ "$COUNT" -lt 2 ]; then
    echo "Expected the hero line and the download section to name v$VERSION; found $COUNT. Check docs/index.html." >&2
    exit 1
fi
echo "docs/index.html now names Markify $VERSION."
