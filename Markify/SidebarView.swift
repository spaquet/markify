//
//  SidebarView.swift
//  Markify
//
//  Created by Stéphane PAQUET on 5/5/25.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ListButtonIdentifier: Identifiable {
    let id = UUID()
}

struct SidebarView: View {
    @Binding var content: String
    @EnvironmentObject var settings: AppSettings
    @State private var files: [FileInfo] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var linkTitle: String = ""
    @State private var showLinkDialog = false
    @State private var selectedLinkURL: URL?
    @State private var listType: ListType = .bulleted
    @State private var showListPicker = false
    @State private var isWebLink: Bool = false
    @State private var linkURL: String = ""
    @State private var listButtonId: ListButtonIdentifier? = nil

    // Reference to the document from ContentView for file operations
    var document: MarkifyDocument?
    
    enum ListType {
        case bulleted, numbered
    }

    struct FileInfo: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let modified: Date
    }

    var body: some View {
        VStack(spacing: 0) {
            // Recent Files Section
            if settings.showRecentFiles {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Files")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    if files.isEmpty {
                        Text("No recent files")
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(files.prefix(settings.recentFilesCount)) { file in
                            Button(action: {
                                loadFile(at: file.url)
                            }) {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(.secondary)

                                    Text(file.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 12)
            }
            
            // Insert Tools Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Insert")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                // Image Button
                Button(action: {
                    insertImage()
                }) {
                    HStack {
                        Image(systemName: "photo")
                            .frame(width: 24)
                        Text("Image")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.vertical, 2)
                
                // Link Button
                Button(action: {
                    insertLink()
                }) {
                    HStack {
                        Image(systemName: "link")
                            .frame(width: 24)
                        Text("Link")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.vertical, 2)
                
                // Task Button
                Button(action: {
                    insertTask()
                }) {
                    HStack {
                        Image(systemName: "checkmark.square")
                            .frame(width: 24)
                        Text("Task")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.vertical, 2)
                
                // List Button
                Button(action: {
                    listButtonId = ListButtonIdentifier() // Create new identifier to trigger popover
                }) {
                    HStack {
                        Image(systemName: "list.bullet")
                            .frame(width: 24)
                        Text("List")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            
            Spacer()
        }
        .frame(minWidth: 200)
        .onAppear { refreshFiles() }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showLinkDialog) {
            VStack(spacing: 16) {
                Text("Insert Link")
                    .font(.headline)
                
                Picker("Link Type", selection: $isWebLink) {
                    Text("Markdown File").tag(false)
                    Text("Website").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                TextField("Link Title (Optional)", text: $linkTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 300)
                
                if isWebLink {
                    TextField("Website URL", text: $linkURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300)
                } else {
                    HStack {
                        Text(selectedLinkURL?.lastPathComponent ?? "No file selected")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 200, alignment: .leading)
                        
                        Button("Browse...") {
                            showLinkDialog = false
                            
                            // Need to use async to prevent UI issues
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [UTType.markdown, UTType.mdx]
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                
                                if panel.runModal() == .OK, let url = panel.url {
                                    selectedLinkURL = url
                                    linkTitle = linkTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : linkTitle
                                    showLinkDialog = true
                                }
                            }
                        }
                    }
                }
                
                HStack {
                    Button("Cancel") {
                        showLinkDialog = false
                    }
                    
                    Spacer()
                    
                    Button("Insert") {
                        insertLinkWithTitle()
                        showLinkDialog = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWebLink && linkURL.isEmpty)
                }
                .padding(.horizontal)
            }
            .padding()
            .frame(width: 340, height: 220)
        }
        .popover(item: $listButtonId, arrowEdge: .leading) { _ in
            VStack(spacing: 8) {
                Text("Choose List Type")
                    .font(.headline)
                    .padding(.top)
                
                Button(action: {
                    insertList(type: .bulleted)
                    listButtonId = nil
                }) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Bulleted List")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 4)
                
                Button(action: {
                    insertList(type: .numbered)
                    listButtonId = nil
                }) {
                    HStack {
                        Image(systemName: "list.number")
                        Text("Numbered List")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 4)
            }
            .padding()
            .frame(width: 200)
        }
    }

    private func refreshFiles() {
        // Get recent documents from NSDocumentController
        let docController = NSDocumentController.shared
        let recentDocURLs = docController.recentDocumentURLs

        // Convert to our FileInfo model
        files = recentDocURLs.compactMap { url in
            guard url.pathExtension == "md" || url.pathExtension == "mdx" else { return nil }

            do {
                let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .nameKey])
                return FileInfo(
                    url: url,
                    name: attributes.name ?? url.lastPathComponent,
                    modified: attributes.contentModificationDate ?? Date()
                )
            } catch {
                print("Error getting attributes for \(url): \(error)")
                return nil
            }
        }
    }

    private func loadFile(at url: URL) {
        do {
            content = try String(contentsOf: url, encoding: .utf8)
            
            // Attempt to open the document in the app
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            ) { (document, documentWasAlreadyOpen, error) in
                if let error = error {
                    errorMessage = "Failed to open document: \(error.localizedDescription)"
                    showError = true
                }
            }
        } catch {
            errorMessage = "Failed to open file: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let imageURL = panel.url {
            // If document is saved, use relative path, otherwise use absolute path
            if let docURL = document?.fileURL {
                let targetDir = docURL.deletingLastPathComponent().appendingPathComponent("images")
                
                // Create images directory if it doesn't exist
                do {
                    try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                    
                    // Copy the image to the images directory
                    let destinationURL = targetDir.appendingPathComponent(imageURL.lastPathComponent)
                    
                    // If file already exists, don't copy it again
                    if !FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.copyItem(at: imageURL, to: destinationURL)
                    }
                    
                    // Create relative path for the markdown
                    let relativePath = relativePath(from: destinationURL, to: docURL)
                    content += "\n![Image](\(relativePath))"
                } catch {
                    errorMessage = "Failed to copy image: \(error.localizedDescription)"
                    showError = true
                }
            } else {
                // For unsaved documents, just use the absolute path for now
                content += "\n![Image](\(imageURL.path))"
            }
        }
    }

    private func insertLink() {
        // Reset states
        linkTitle = ""
        linkURL = ""
        isWebLink = false
        showLinkDialog = true
    }
    
    private func insertLinkWithTitle() {
        if isWebLink {
            // For web links, use the URL directly
            if !linkURL.hasPrefix("http://") && !linkURL.hasPrefix("https://") {
                linkURL = "https://" + linkURL
            }
            
            let displayTitle = linkTitle.isEmpty ? linkURL : linkTitle
            content += "\n[\(displayTitle)](\(linkURL))"
        } else if let url = selectedLinkURL {
            // For file links
            let displayTitle = linkTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : linkTitle
            
            // If document is saved, use relative path, otherwise use absolute path
            if let docURL = document?.fileURL {
                let relativePath = relativePath(from: url, to: docURL)
                content += "\n[\(displayTitle)](\(relativePath))"
            } else {
                // For unsaved documents, use a cleaner format with a URI scheme
                content += "\n[\(displayTitle)](file://\(url.path))"
            }
        }
    }
    
    private func insertTask() {
        content += "\n- [ ] New task"
    }
    
    private func insertList(type: ListType) {
        switch type {
        case .bulleted:
            content += "\n\n- Item 1\n- Item 2\n- Item 3"
        case .numbered:
            content += "\n\n1. Item 1\n2. Item 2\n3. Item 3"
        }
    }
    
    private func relativePath(from source: URL, to base: URL) -> String {
        let sourceComponents = source.standardized.pathComponents
        let baseComponents = base.standardized.pathComponents
        var i = 0
        while i < min(sourceComponents.count, baseComponents.count), sourceComponents[i] == baseComponents[i] {
            i += 1
        }
        let up = Array(repeating: "..", count: baseComponents.count - i - 1)
        let down = sourceComponents[i...]
        return (up + down).joined(separator: "/")
    }
}
