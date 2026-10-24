#!/bin/bash
# Writes one Sparkle appcast for a release: a single item for one update archive, with the
# release notes and the archive's EdDSA signature. The build job writes the env file (see release-dmg.yml).
#
# Usage: scripts/write-appcast.sh <tag> <repo> <update env file> <appcast output>
set -euo pipefail
TAG=${1:?usage: write-appcast.sh <tag> <repo> <env file> <output>}
REPO=${2:?usage: write-appcast.sh <tag> <repo> <env file> <output>}
ENV_FILE=${3:?usage: write-appcast.sh <tag> <repo> <env file> <output>}
OUT=${4:?usage: write-appcast.sh <tag> <repo> <env file> <output>}

source "$ENV_FILE"
if [ -z "${ENCLOSURE_ATTRIBUTES:-}" ]; then
  echo "::error::The update archive $ARCHIVE wasn't signed." >&2
  exit 1
fi
# The release notes, shown by Sparkle as Markdown; CDATA can't contain "]]>".
NOTES=$(gh release view "$TAG" --json body -q .body | sed 's/]]>/]]]]><![CDATA[>/g')

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Markify</title>
    <link>https://github.com/${REPO}</link>
    <item>
      <title>Markify ${SHORT_VERSION}</title>
      <link>https://github.com/${REPO}/releases/tag/${TAG}</link>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <pubDate>$(date -u -R)</pubDate>
      <description sparkle:format="markdown"><![CDATA[${NOTES}]]></description>
      <enclosure url="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}" ${ENCLOSURE_ATTRIBUTES} type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT"
cat "$OUT"
