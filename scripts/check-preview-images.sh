#!/bin/bash
# Exercises the real XPC image helper from a sandboxed client with no folder grants.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DERIVED="${MARKIFY_PREVIEW_DERIVED:-/private/tmp/markify-preview-check-derived}"
xcodebuild -quiet -project Markify.xcodeproj -scheme PreviewImages -configuration Debug \
    -derivedDataPath "$DERIVED" build CODE_SIGNING_ALLOWED=NO
CHECK_DIR=$(mktemp -d /private/tmp/markify-preview-check.XXXXXX)
trap 'rm -rf "$CHECK_DIR"' EXIT
HOST="$CHECK_DIR/PreviewHost.app"
APP="$HOST/Contents/PlugIns/PreviewCheck.appex"
mkdir -p "$HOST/Contents/MacOS"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/XPCServices"
cp -R "$DERIVED/Build/Products/Debug/PreviewImages.xpc" "$APP/Contents/XPCServices/"
cp docs/images/app-icon.png "$CHECK_DIR/picture one.png"
cp docs/images/app-icon.png "$CHECK_DIR/picture two.png"
printf 'this is not an image' > "$CHECK_DIR/fake.png"
printf '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>' > "$CHECK_DIR/vector.svg"
cat > "$CHECK_DIR/fixture.md" <<'MD'
![Markdown image](picture%20one.png)
<img src="picture two.png">
![Invalid image](fake.png)
![Missing image](missing.png)
![Vector image](vector.svg)
MD
cp "$CHECK_DIR/fixture.md" "$CHECK_DIR/fixture.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PreviewCheck</string>
<key>CFBundleIdentifier</key><string>com.stephanepaquet.Markify.PreviewCheck</string>
<key>CFBundlePackageType</key><string>XPC!</string>
</dict></plist>
PLIST
cat > "$CHECK_DIR/Check.swift" <<'SWIFT'
import Foundation

@main struct Check {
    static func main() async {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let read = try? Data(contentsOf: fixture)
        precondition(read == nil, "Client must have no direct access to the fixture")
        let images = await PreviewImageClient.images(for: fixture)
        precondition(Set(images.keys) == ["picture%20one.png", "picture two.png", "vector.svg"], "Unexpected images: \(images.keys)")
        precondition(images["picture%20one.png"]?.hasPrefix("data:image/png;base64,") == true)
        precondition(images["vector.svg"]?.hasPrefix("data:image/svg+xml;base64,") == true)
        let readme = URL(fileURLWithPath: CommandLine.arguments[2])
        let projectImages = await PreviewImageClient.images(for: readme)
        precondition(projectImages.count == 10, "README images missing: \(projectImages.keys)")
        precondition(projectImages["docs/images/og-image.jpg"]?.hasPrefix("data:image/jpeg;base64,") == true)
        precondition(projectImages["docs/images/screens/1a.webp"]?.hasPrefix("data:image/webp;base64,") == true)
        let unsupported = await PreviewImageClient.images(for: fixture.deletingPathExtension().appendingPathExtension("txt"))
        precondition(unsupported.isEmpty)
        print("Sandboxed XPC check passed: Markdown and HTML images, percent-encoded paths, SVG, README JPEG/PNG/WebP, invalid and missing files.")
    }
}
SWIFT
swiftc -swift-version 6 -application-extension -parse-as-library QuickLook/PreviewImageProtocol.swift QuickLook/PreviewImageClient.swift \
    "$CHECK_DIR/Check.swift" -o "$APP/Contents/MacOS/PreviewCheck"
cp "$APP/Contents/MacOS/PreviewCheck" "$HOST/Contents/MacOS/PreviewHost"
cat > "$HOST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PreviewHost</string>
<key>CFBundleIdentifier</key><string>com.stephanepaquet.Markify.PreviewHost</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
# Match release signing: sign inside out, restore the extension's entitlements, then seal the app.
codesign --force --deep --sign - "$HOST"
codesign --force --sign - --entitlements QuickLook/QuickLook.entitlements "$APP"
codesign --force --sign - "$HOST"
codesign --verify --deep --strict "$HOST"
"$APP/Contents/MacOS/PreviewCheck" "$CHECK_DIR/fixture.md" "$ROOT/README.md"
