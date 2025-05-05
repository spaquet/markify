//
//  SidebarView.swift
//  Markify
//
//  Created by Stéphane PAQUET on 5/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Binding var content: String
    @State private var files: [FileInfo] = []
    @State private var deletedFiles: [FileInfo] = []
    @State private var showError = false
    @State private var errorMessage = ""

    struct FileInfo: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let modified: Date
    }

    var body: some View {
        List {
            Section("Recent Files") {
                ForEach(files) { file in
                    Button(file.name) {
                        loadFile(at: file.url)
                    }
                }
            }
            Section("Recently Deleted") {
                ForEach(deletedFiles) { file in
                    Button(file.name) {
                        restoreFile(at: file.url)
                    }
                }
            }
        }
        .onAppear { refreshFiles() }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func refreshFiles() {
        do {
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let trashDir = documentsDir.appendingPathComponent(".trash")
            try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

            let mdFiles = try FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: [.contentModificationDateKey, .nameKey])
                .filter { $0.pathExtension == "md" || $0.pathExtension == "mdx" }
            files = try mdFiles.map {
                let attributes = try $0.resourceValues(forKeys: [.contentModificationDateKey, .nameKey])
                return FileInfo(url: $0, name: attributes.name ?? $0.lastPathComponent, modified: attributes.contentModificationDate ?? Date())
            }.sorted { $0.modified > $1.modified }

            let deletedFiles = try FileManager.default.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: [.contentModificationDateKey, .nameKey])
                .filter { $0.pathExtension == "md" || $0.pathExtension == "mdx" }
            self.deletedFiles = try deletedFiles.map {
                let attributes = try $0.resourceValues(forKeys: [.contentModificationDateKey, .nameKey])
                return FileInfo(url: $0, name: attributes.name ?? $0.lastPathComponent, modified: attributes.contentModificationDate ?? Date())
            }.sorted { $0.modified > $1.modified }
        } catch {
            errorMessage = "Failed to load files: \(error.localizedDescription)"
            showError = true
        }
    }

    private func loadFile(at url: URL) {
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            errorMessage = "Failed to open file: \(error.localizedDescription)"
            showError = true
        }
    }

    private func restoreFile(at url: URL) {
        do {
            let originalURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: originalURL)
            refreshFiles()
        } catch {
            errorMessage = "Failed to restore file: \(error.localizedDescription)"
            showError = true
        }
    }
}
