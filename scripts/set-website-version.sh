#!/bin/bash
# Points the website's version line and download section at a release:
# the download buttons' version label (also on compare.html and okf.html), the download section's releases/tag/vX link and the structured data's softwareVersion in docs/index.html
# (and "Version X" / "Markify X ·" if a page brings them back).
# The download buttons' links use releases/latest/download/…, so they need no change.
#
# Usage: scripts/set-website-version.sh 1.61
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: set-website-version.sh <version>}
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Not a version: $VERSION" >&2; exit 1; }

perl -pi -e "s{releases/tag/v[0-9]+(?:\.[0-9]+){1,2}}{releases/tag/v$VERSION}g;
             s{Version [0-9]+(?:\.[0-9]+){1,2}}{Version $VERSION}g;
             s{Markify [0-9]+(?:\.[0-9]+){1,2} ·}{Markify $VERSION ·}g;
             s{data-version=\"v[0-9]+(?:\.[0-9]+){1,2}\"}{data-version=\"v$VERSION\"}g;
             s{ · v[0-9]+(?:\.[0-9]+){1,2}<}{ · v$VERSION<}g;
             s{\"softwareVersion\":\"[0-9.]+\"}{\"softwareVersion\":\"$VERSION\"}g" docs/index.html
# Other pages with a download button carry the same label.
perl -pi -e "s{data-version=\"v[0-9]+(?:\.[0-9]+){1,2}\"}{data-version=\"v$VERSION\"}g;
             s{ · v[0-9]+(?:\.[0-9]+){1,2}<}{ · v$VERSION<}g" docs/compare.html docs/okf.html

if ! grep -q "releases/tag/v$VERSION" docs/index.html || ! grep -q "\"softwareVersion\":\"$VERSION\"" docs/index.html; then
    echo "Expected the download section and softwareVersion to name $VERSION. Check docs/index.html." >&2
    exit 1
fi
echo "docs/index.html now names Markify $VERSION."
