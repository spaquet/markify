#!/bin/bash
# Refresh current branding exports from the app's SVG and Icon Composer sources.
# Requires librsvg (rsvg-convert) and ImageMagick (magick).
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in rsvg-convert magick python3; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
SOURCE=Markify/Assets.xcassets/AppIcon.appiconset/AppIcon.svg
IMAGES=docs/images
PACK=marketing/AppIcons
cp "$SOURCE" "$IMAGES/logo.svg"
rsvg-convert -w 256 -h 256 "$SOURCE" -o "$IMAGES/app-icon.png"
rsvg-convert -w 1024 -h 1024 "$SOURCE" -o "$IMAGES/markify-app-icon-1024.png"
rsvg-convert -w 64 -h 64 "$SOURCE" -o "$IMAGES/favicon.png"
magick "$IMAGES/markify-app-icon-1024.png" -define icon:auto-resize=48,32,16 docs/favicon.ico
# Inline the logo so the social SVG remains self-contained, including in <img>.
python3 - <<'PYTHON'
from pathlib import Path
import re
logo = Path('docs/images/logo.svg').read_text()
body = re.search(r'<svg\b[^>]*>(.*)</svg>', logo, re.S).group(1)
body = re.sub(r'<(?:title|desc)\b[^>]*>.*?</(?:title|desc)>', '', body, flags=re.S)
path = Path('docs/images/og-image.svg')
source = path.read_text()
source = re.sub(r'<!-- BRAND_MARK_START -->.*?<!-- BRAND_MARK_END -->',
    '<!-- BRAND_MARK_START -->\n  <svg x="858" y="160" width="340" height="340" viewBox="0 0 1024 1024">' + body + '</svg>\n  <!-- BRAND_MARK_END -->',
    source, flags=re.S)
path.write_text(source)
PYTHON
rsvg-convert "$IMAGES/og-image.svg" | magick - -background '#f4f3ef' -alpha remove -quality 92 "$IMAGES/og-image.jpg"
mkdir -p "$PACK/Assets.xcassets/AppIcon.appiconset" "$PACK/AppIcon.icon/Assets"
cp Markify/Assets.xcassets/AppIcon.appiconset/*.png "$PACK/Assets.xcassets/AppIcon.appiconset/"
cp Markify/Assets.xcassets/AppIcon.appiconset/Contents.json "$PACK/Assets.xcassets/AppIcon.appiconset/Contents.json"
cp "$SOURCE" "$PACK/Assets.xcassets/AppIcon.appiconset/AppIcon.svg"
cp Markify/AppIcon.icon/icon.json "$PACK/AppIcon.icon/icon.json"
cp Markify/AppIcon.icon/Assets/* "$PACK/AppIcon.icon/Assets/"
cp "$IMAGES/markify-app-icon-1024.png" "$PACK/appstore.png"
magick "$IMAGES/markify-app-icon-1024.png" -resize 512x512 "$PACK/playstore.png"
echo "Brand assets built. Run scripts/build-help.sh to refresh the Help Book icon."
