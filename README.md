# Markify

[![GitHub Release](https://img.shields.io/github/v/release/spaquet/markify)](https://github.com/spaquet/markify/releases)
[![License](https://img.shields.io/badge/license-Commons%20Clause%20%2B%20MIT-blue)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13.0+-lightgrey)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange)](https://swift.org)

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

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for building from source)

## Installation

### From Source

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

## Support

For bug reports, feature requests, and questions, please use the [GitHub Issues](https://github.com/spaquet/markify/issues) page.
