//
//  ContentView.swift
//  Markify
//
//  Created by Stéphane PAQUET on 5/5/25.
//

import SwiftUI
import MarkdownUI
import PhotosUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @ObservedObject var document: MarkifyDocument
    @State private var showEditor = true
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var documentTitle: String = "Untitled"
    
    var body: some View {
        NavigationSplitView {
            SidebarView(content: $document.content)
        } detail: {
            HStack {
                if showEditor {
                    TextEditor(text: $document.content)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(minWidth: 300)
                        .background(Color(.windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Markdown(document.content)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem {
                    Button(action: { showEditor.toggle() }) {
                        Image(systemName: showEditor ? "eye.slash" : "eye")
                    }
                    .help(showEditor ? "Hide Editor" : "Show Editor")
                }
                ToolbarItem {
                    PhotosPicker("Add Image", selection: $selectedItems, matching: .images)
                        .onChange(of: selectedItems) { items in
                            handleImageSelection(items)
                        }
                }
                ToolbarItem {
                    Button(action: { insertLink() }) {
                        Image(systemName: "link")
                    }
                    .help("Insert Link to Markdown File")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .navigationTitle(documentTitle)
            .onAppear {
                updateDocumentTitle()
            }
            .onChange(of: document.fileURL) { _ in
                updateDocumentTitle()
            }
        }
    }
    
    private func updateDocumentTitle() {
        if let url = document.fileURL {
            documentTitle = url.lastPathComponent
        } else {
            documentTitle = "Untitled"
        }
    }
    
    private func handleImageSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        
        // Create temporary directory for images if document not saved yet
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDir = documentsDirectory.appendingPathComponent("MarkifyImages")
        
        // If document has a file URL, use that directory instead
        let targetDir = document.fileURL?.deletingLastPathComponent().appendingPathComponent("images") ?? imagesDir
        
        Task {
            do {
                try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
                
                if let data = try await item.loadTransferable(type: Data.self) {
                    let imageURL = targetDir.appendingPathComponent("image_\(UUID().uuidString).jpg")
                    try data.write(to: imageURL)
                    
                    // Use relative path if document is saved, otherwise use absolute path
                    if let docURL = document.fileURL {
                        let relativePath = relativePath(from: imageURL, to: docURL)
                        document.content += "\n![Image](\(relativePath))"
                    } else {
                        document.content += "\n![Image](\(imageURL.path))"
                    }
                }
            } catch {
                errorMessage = "Failed to add image: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func insertLink() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.markdown, UTType.mdx]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            // If document is saved, use relative path, otherwise use absolute path
            if let docURL = document.fileURL {
                let relativePath = relativePath(from: url, to: docURL)
                document.content += "\n[Link](\(relativePath))"
            } else {
                document.content += "\n[Link](\(url.path))"
            }
        }
    }
    
    private func relativePath(from source: URL, to base: URL) -> String {
        let sourceComponents = source.standardized.pathComponents
        let baseComponents = base.standardized.pathComponents
        var i = 0
        while i < min(sourceComponents.count, baseComponents.count), sourceComponents[i] == baseComponents[i] {
            i += 1
        }
        let up = Array(repeating: "..", count: baseComponents.count - i)
        let down = sourceComponents[i...]
        return (up + down).joined(separator: "/")
    }
}
