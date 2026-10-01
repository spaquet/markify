#!/bin/bash
# Removes stale Markify copies from LaunchServices and PlugInKit.
#
# Xcode registers every Markify.app it builds with LaunchServices (no build
# setting turns that off), so each new build folder — a throwaway
# -derivedDataPath, a Release build, a mounted DMG — adds another Markify
# under System Settings › General › Login Items & Extensions › Extensions.
#
# Keeps /Applications/Markify.app, ~/Applications/Markify.app and the Debug
# app in Xcode's default DerivedData; everything else is unregistered.
#   --all       also unregister the DerivedData Debug app
#   --delete    also delete stale build folders under /private/tmp
#   --dry-run   only list what would change
set -euo pipefail

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
KEEP_DERIVED=1 DELETE=0 DRY=0
for arg in "$@"; do
    case "$arg" in
        --all) KEEP_DERIVED=0 ;;
        --delete) DELETE=1 ;;
        --dry-run) DRY=1 ;;
        *) echo "usage: $0 [--all] [--delete] [--dry-run]" >&2; exit 2 ;;
    esac
done

keep() {
    case "$1" in
        /Applications/Markify.app|"$HOME/Applications/Markify.app") return 0 ;;
        "$HOME"/Library/Developer/Xcode/DerivedData/Markify-*/Build/Products/Debug/Markify.app) [ "$KEEP_DERIVED" = 1 ] ;;
        *) return 1 ;;
    esac
}

run() { if [ "$DRY" = 1 ]; then echo "  would run: $*"; else "$@" || true; fi; }

# Top-level Markify bundles (the app and the UI test runner), not the bundles nested inside them.
apps=$("$LSREGISTER" -dump \
    | sed -n 's/^path: *\(.*\) (0x[0-9a-f]*)$/\1/p' \
    | grep -E '/(Markify|MarkifyUITests-Runner)\.app$' \
    | grep -v '\.app/.*\.app$' | sort -u)

while IFS= read -r app; do
    [ -n "$app" ] || continue
    if keep "$app"; then echo "keep   $app"; continue; fi
    echo "remove $app"
    [ -d "$app/Contents/PlugIns" ] && for appex in "$app"/Contents/PlugIns/*.appex; do
        [ -e "$appex" ] && run pluginkit -r "$appex"
    done
    run "$LSREGISTER" -u "$app"
    if [ "$DELETE" = 1 ] && [ -d "$app" ]; then
        # Delete the whole derived-data folder a /tmp build came from.
        case "$app" in
            /private/tmp/*/Build/Products/*|/tmp/*/Build/Products/*) run rm -rf "${app%%/Build/Products/*}" ;;
            /private/tmp/*|/tmp/*) run rm -rf "$app" ;;
        esac
    fi
done <<< "$apps"

# Extension records whose app is gone or was just unregistered.
pluginkit -mAv 2>/dev/null | awk '$1 ~ /^com\.stephanepaquet\.Markify/ { print $NF }' | while IFS= read -r appex; do
    app="${appex%/Contents/PlugIns/*}"
    if ! keep "$app"; then echo "remove $appex"; run pluginkit -r "$appex"; fi
done

[ "$DRY" = 1 ] || "$LSREGISTER" -gc >/dev/null 2>&1 || true
echo "Done. Reopen System Settings to see the updated Extensions list."
