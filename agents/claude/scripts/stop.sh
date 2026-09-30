#!/bin/bash
# Optional Stop hook. Viewer failures must never block Claude's conversation.
set -uo pipefail
if ! command -v jq >/dev/null; then
    echo 'Markify automatic viewing requires jq; install it or disable this hook.' >&2
    exit 0
fi
input=$(cat)
if ! printf '%s' "$input" | jq -e '.stop_hook_active != true and (.last_assistant_message | type == "string" and length > 0)' >/dev/null 2>&1; then exit 0; fi
base=$(printf '%s' "$input" | jq -r '.cwd // empty')
if [ -z "$base" ]; then base="$PWD"; fi
printf '%s' "$input" | jq -j '.last_assistant_message' | bash "$(dirname "$0")/view.sh" - --title 'Claude report' --base "$base" || echo 'Markify could not open this response.' >&2
exit 0
