# Markify

[![GitHub Release](https://img.shields.io/github/v/release/spaquet/markify)](https://github.com/spaquet/markify/releases)
[![License](https://img.shields.io/badge/license-Commons%20Clause%20%2B%20MIT-blue)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14.8%2B%2C%2026-lightgrey)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.2+-orange)](https://swift.org)

A beautiful, minimal markdown editor for macOS with live preview. Write and preview Markdown (.md) and MDX (.mdx) files with a clean split-pane interface.

## Features

- **Live Preview**: See your markdown rendered in real-time as you type
- **Split-Pane Interface**: View editor and preview side-by-side
- **MDX Support**: Edit both standard Markdown and MDX files
- **GitHub-Flavored Markdown**: Full support for GitHub's markdown extensions
- **Recent Files**: Quick access to your recently edited documents
- **Insert Tools**: Convenient buttons for inserting images, links, tasks, and lists
- **Toggle Editor**: Hide/show the editor pane with a single click
- **Native macOS Integration**: Built with SwiftUI for seamless macOS experience
- **Auto-Save**: Documents are automatically saved as you work

## Download

Get the latest version of Markify from the [Releases page](https://github.com/spaquet/markify/releases).

### Pre-built Binaries

Two versions are available for download:

- **`markify-as.dmg`** - For Apple Silicon Macs (M1, M2, M3, M4 and newer)
- **`markify-intel.dmg`** - For Intel Macs

Not sure which one to choose? Check your Mac:
- Apple menu → About This Mac → Look at the "Chip" field
- If it says "Apple M1", "M2", "M3", or "M4": Download **Apple Silicon (as)**
- If it says "Intel Core": Download **Intel**

### Installation from DMG

1. Download the appropriate DMG file for your Mac
2. Double-click the DMG file to open it
3. Drag the **Markify** app to your **Applications** folder
4. On first launch, you may see a security warning (since the app is unsigned)
   - Right-click on Markify in Applications folder
   - Select "Open" from the context menu
   - Click "Open" in the security dialog
5. On subsequent launches, you can open Markify normally from Applications or Spotlight

> **Note**: Markify is currently distributed as an unsigned application. You will see a security warning on first launch. This is expected and safe. For more information about unsigned apps, see the [FAQ](#faq).

## Requirements

- **macOS 14.8** or later (supports macOS 14.8+, 15.*, and macOS 26)
- **Xcode 26** or later (for building from source)

## Building from Source

### Installation

1. Clone the repository:
```bash
git clone https://github.com/spaquet/markify.git
cd markify
```

2. Open the Xcode project:
```bash
open Markify.xcodeproj
```

3. Select the "Markify" scheme and press Cmd+R to build and run, or Cmd+B to build.

4. The app will be built to `DerivedData/` and can be installed to `/Applications`:
```bash
open build/Release/Markify.app
```

## Usage

- **Open a File**: Use File → Open or Cmd+O to open an existing markdown file
- **Create New File**: Use File → New or Cmd+N to create a new document
- **Insert Elements**: Use the sidebar tools to quickly insert images, links, tasks, and lists
- **Toggle Editor**: Click the eye icon in the toolbar to show/hide the editor pane
- **Save**: Use File → Save or Cmd+S to save your document

## Development

### Build

```bash
xcodebuild -project Markify.xcodeproj -scheme Markify -configuration Release build
```

### Test

```bash
xcodebuild -project Markify.xcodeproj -scheme Markify test
```

See [CLAUDE.md](CLAUDE.md) for comprehensive development documentation.

## Architecture

Markify follows Apple's document-based app pattern using SwiftUI and `ReferenceFileDocument`. The architecture consists of:

- **MarkifyApp**: Entry point and document group configuration
- **MarkifyDocument**: File I/O and document model for .md and .mdx files
- **ContentView**: Main UI with split-pane layout (editor + preview)
- **SidebarView**: Toolbar with recent files and insert tools

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation.

## Dependencies

- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) - Markdown rendering
- [NetworkImage](https://github.com/gonzalezreal/NetworkImage) - Image loading support
- [swift-cmark](https://github.com/swiftlang/swift-cmark) - CommonMark parsing with GitHub Flavored Markdown

## License

Markify is available under the Commons Clause License with MIT as the base license. See [LICENSE](LICENSE) for details.

**In summary:**
- ✅ You may compile and use Markify personally
- ✅ You may modify the source code for personal use
- ❌ Commercial use requires written permission
- ❌ Integration into other products or commercial services is prohibited without written permission
- ❌ Distribution on the App Store or other commercial platforms requires written permission

For commercial licensing or exceptions, please contact the maintainer.

## Contributing

Contributions are welcome, but please note the licensing restrictions. Any contributions will be subject to the same license terms.

## Author

Created by [Stéphane PAQUET](https://github.com/spaquet)

## FAQ

### Why is Markify unsigned?

Markify is currently distributed as an unsigned application without Apple's Developer ID certificate. This means:

- **First launch security warning**: macOS will show a warning dialog asking if you want to open the app
- **Workaround**: Right-click the app and select "Open" - this bypasses the Gatekeeper check
- **Future plans**: As Markify grows, we plan to add code signing and notarization for a cleaner user experience

### Is it safe to use an unsigned app?

Yes, absolutely! The source code is open and available on GitHub. You can review it yourself or build it directly from source. Unsigned just means we haven't purchased an Apple Developer ID certificate yet.

### How do I know which version to download?

Check your Mac's architecture:
1. Click the Apple menu in the top-left
2. Select "About This Mac"
3. Look at the "Chip" field:
   - **Apple M1, M2, M3, M4**: Download `markify-as.dmg` (Apple Silicon)
   - **Intel Core**: Download `markify-intel.dmg` (Intel)

### Can I verify the downloaded file is authentic?

Yes! Each DMG file comes with a SHA256 checksum file (`.sha256`). After downloading:

```bash
# Navigate to your Downloads folder
cd ~/Downloads

# Verify the checksum
shasum -c markify-as.dmg.sha256
# or
shasum -c markify-intel.dmg.sha256
```

You should see `OK` if the file is authentic.

## Support

For bug reports, feature requests, and questions, please use the [GitHub Issues](https://github.com/spaquet/markify/issues) page.
