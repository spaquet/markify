#!/bin/bash
# Builds Markify's help from help/*.md: the app's Help Book (Markify/Resources/Markify.help, indexed for the Help
# menu's search) and the website's help, FAQ and legal pages with sitemap.xml, robots.txt and llms.txt.
# Run it after editing help/ or LICENSE, and before a release (the /deploy skill does).
#
# Usage: scripts/build-help.sh [--check]   --check fails if the app's Help Book is out of date.
set -euo pipefail
cd "$(dirname "$0")/.."

swift run --quiet --package-path Tools/HelpBuilder HelpBuilder "$PWD"

LPROJ=Markify/Resources/Markify.help/Contents/Resources/en.lproj
hiutil -I corespotlight -Caf "$LPROJ/Markify.helpindex" "$LPROJ"
# The index lists each page's anchor; every page in help/ must be there.
INDEXED=$(hiutil -I corespotlight -Af "$LPROJ/Markify.helpindex" | wc -l | tr -d ' ')
PAGES=$(ls help/*.md | wc -l | tr -d ' ')
[ "$INDEXED" -ge "$PAGES" ] || { echo "The help index has $INDEXED anchors for $PAGES pages." >&2; exit 1; }

if [ "${1:-}" = "--check" ]; then
    # Checks the Help Book, which ships in the app. The website's copy is refreshed when a release is published
    # (see the deploy skill), so it may trail help/ on main. The index is binary and differs on every build.
    PATHS=(Markify/Resources/Markify.help ':!*.helpindex')
    if ! git diff --quiet -- "${PATHS[@]}" || [ -n "$(git ls-files --others --exclude-standard -- "${PATHS[@]}")" ]; then
        git diff --stat -- "${PATHS[@]}" >&2
        git ls-files --others --exclude-standard -- "${PATHS[@]}" >&2
        echo "The Help Book is out of date: run scripts/build-help.sh and commit Markify/Resources/Markify.help." >&2
        exit 1
    fi
fi
echo "Help built."
