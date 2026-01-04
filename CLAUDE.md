# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Markify is a macOS markdown editor built with SwiftUI. It supports reading and editing both `.md` and `.mdx` files, with a split-view interface showing live markdown preview using the MarkdownUI library. The app follows the macOS document-based app pattern using `ReferenceFileDocument`.

## Build & Development Commands

### Building and Running

```bash
# Build the app for Release
xcodebuild -project Markify.xcodeproj -scheme Markify -configuration Release build

# Build for Debug
xcodebuild -project Markify.xcodeproj -scheme Markify -configuration Debug build

# Run the app from Xcode
open Markify.xcodeproj
```

### Testing

```bash
# Run all tests
xcodebuild -project Markify.xcodeproj -scheme Markify test

# Run specific test target
xcodebuild -project Markify.xcodeproj -scheme Markify -only-testing MarkifyTests test

# Run UI tests
xcodebuild -project Markify.xcodeproj -scheme Markify -only-testing MarkifyUITests test
```

## Architecture & Key Components

### File Structure

- **MarkifyApp.swift**: Entry point using `@main` and `DocumentGroup` scene for the document-based app pattern
- **MarkifyDocument.swift**: `ReferenceFileDocument` subclass that handles file I/O for `.md` and `.mdx` files. Manages content serialization and deserialization. Note: `fileURL` is accessed via NSDocumentController rather than stored directly.
- **ContentView.swift**: Main UI composed of a `NavigationSplitView` with:
  - Left sidebar: `SidebarView`
  - Right detail: Split HStack with TextEditor (editor pane) and Markdown preview pane using MarkdownUI
  - Toolbar button to toggle editor visibility
- **SidebarView.swift**: Sidebar with three sections:
  - Recent Files: Lists up to 5 recent markdown files from NSDocumentController
  - Insert Tools: Buttons for inserting images, links, tasks, and lists
  - Handles file dialogs and relative path calculations for images and links

### Key Design Patterns

1. **Document-Based App**: Uses SwiftUI's `DocumentGroup` and `ReferenceFileDocument` for native macOS file handling with auto-save capabilities

2. **File URL Handling**: `MarkifyDocument.fileURL` uses NSDocumentController internally rather than storing state directly. This is important for proper integration with macOS file operations.

3. **Relative Paths**: Images and file links use relative paths when the document is saved, falling back to absolute paths for unsaved documents

4. **State Management**:
   - `@ObservedObject var document` in ContentView binds to the MarkifyDocument
   - `@Binding` in SidebarView for content editing
   - Local @State for UI state (dialogs, visibility toggles)

### External Dependencies

- **MarkdownUI** (2.4.1): Provides markdown rendering with GitHub theme support
- **swift-markdown-ui**: Package dependency for MarkdownUI
- **NetworkImage** (6.0.1): Image loading support
- **cmark-gfm** (0.7.1): CommonMark parsing with GitHub Flavored Markdown extensions

## Key Implementation Details

### Image Insertion (SidebarView:311)

- Creates `images/` subdirectory relative to the markdown file
- Copies selected image to this directory
- Uses relative paths in markdown syntax
- For unsaved documents, uses absolute paths

### Link Insertion (SidebarView:348)

- Supports both web links (with automatic `https://` prefix) and file links
- File browser limited to `.md` and `.mdx` files
- Relative path calculation for file links when document is saved

### File Operations

- Recent files fetched from `NSDocumentController.shared.recentDocumentURLs`
- File info includes name, URL, and modification date
- Loading files opens them in new windows via NSDocumentController

## Testing Notes

The test framework uses Swift Testing (not XCTest). Basic test structure is in place in `MarkifyTests.swift` but needs expansion.

## Common Workflows

**Adding UI Elements**: New UI typically goes in ContentView (main interface) or SidebarView (sidebar tools). Remember to update @State or @Binding as needed.

**Modifying Document I/O**: Changes to file reading/writing must be made in MarkifyDocument - specifically the `init(configuration:)` and `fileWrapper(snapshot:configuration:)` methods.

**Adding Sidebar Tools**: Insert new buttons in SidebarView and create corresponding helper functions to manipulate `content` binding.
