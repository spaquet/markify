#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CLI="${1:-MarkifyCLI/.build/debug/markify}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bundle" "$TMP/assets" "$TMP/out"

printf '# Index\n' > "$TMP/bundle/index.md"
printf '%s\n' '---' 'type: note' 'status: unusual' '---' '# Valid' > "$TMP/bundle/note.md"
"$CLI" check "$TMP/bundle" > "$TMP/check.out"
grep -q 'note.md: warning:' "$TMP/check.out"

printf '# Missing type\n' > "$TMP/bundle/bad.md"
if "$CLI" check "$TMP/bundle" > "$TMP/check.out"; then exit 1; fi
grep -q 'bad.md: error:' "$TMP/check.out"

printf 'image bytes' > "$TMP/assets/pic.png"
printf '%s\n' '---' 'title: Exported' '---' '# Heading' '![Image](assets/pic.png)' '[Note](bundle/note.md#part)' > "$TMP/input.md"
cp "$TMP/input.md" "$TMP/original.md"
"$CLI" export "$TMP/input.md" --html --output "$TMP/out/page.html"
grep -q '<title>Exported</title>' "$TMP/out/page.html"
grep -q 'data:image/png;base64,' "$TMP/out/page.html"
grep -q '../bundle/note.md#part' "$TMP/out/page.html"
cmp "$TMP/input.md" "$TMP/original.md"

if "$CLI" export "$TMP/missing.md" --html --output "$TMP/out/missing.html" 2> "$TMP/error.out"; then exit 1; fi
grep -q 'markify:' "$TMP/error.out"
echo 'CLI checks passed.'
