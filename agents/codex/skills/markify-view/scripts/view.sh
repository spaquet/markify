#!/bin/bash
set -euo pipefail
cli="${MARKIFY_CLI:-}"
if [ -z "$cli" ]; then cli=$(command -v markify || true); fi
if [ -z "$cli" ]; then
    app=$(/usr/bin/osascript -e 'POSIX path of (path to application id "com.stephanepaquet.Markify")' 2>/dev/null || true)
    cli="${app%/}/Contents/Helpers/markify"
fi
if [ ! -x "$cli" ]; then
    echo 'Markify is missing. Install it: https://github.com/spaquet/markify/releases/latest (or set MARKIFY_CLI to its bundled executable).' >&2
    exit 1
fi
if ! "$cli" --help | /usr/bin/grep -q 'markify view'; then
    echo 'This Markify CLI does not support view. Update it: https://github.com/spaquet/markify/releases/latest (or set MARKIFY_CLI to a newer executable).' >&2
    exit 1
fi
exec "$cli" view "$@"
