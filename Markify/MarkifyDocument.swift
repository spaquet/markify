//
//  MarkifyDocument.swift
//  Markify
//
//  Created by Stéphane PAQUET on 5/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdown: UTType {
        UTType(importedAs: "net.daringfireball.markdown")
    }
    
    static var mdx: UTType {
        UTType(importedAs: "com.mdx")
    }
}

@MainActor
class MarkifyDocument: ReferenceFileDocument {
    @Published var content: String = ""
    @Published var editingContent: String = ""
    @Published var didAutoSave: Bool = false

    private var saveTask: Task<Void, Error>?

    private func getNSDocument() -> NSDocument? {
        let appDelegate = NSApp.delegate as? NSDocumentController
        return appDelegate?.currentDocument as? NSDocument
    }

    static var readableContentTypes: [UTType] {
        [.markdown, .mdx]
    }

    static var writableContentTypes: [UTType] {
        [.markdown, .mdx]
    }

    init() {
        content = ""
        editingContent = ""
        didAutoSave = false
    }
    
    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = string
        editingContent = string
        didAutoSave = false
        // Don't try to set fileURL here - it's handled by the system
    }

    func debouncedSave(from editingText: String, settings: AppSettings) {
        editingContent = editingText

        // Check if auto-save is enabled
        guard settings.autoSaveEnabled else { return }

        // Cancel the previous save task
        saveTask?.cancel()

        // Schedule a new save task
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Perform the delay off the main actor
                try await Task.sleep(nanoseconds: settings.autoSaveDelayNanoseconds)
                if Task.isCancelled { return }
                // Back on main actor due to @MainActor on the class
                self.content = editingText
                if let nsDoc = self.getNSDocument() {
                    nsDoc.updateChangeCount(.changeDone)
                }
                self.didAutoSave.toggle()
            } catch {
                // Task was cancelled or errored, ignore
                return
            }
        }
    }

    func explicitSave(from editingText: String) {
        // Cancel any pending debounced save
        saveTask?.cancel()
        saveTask = nil

        // Immediately update content and save
        self.content = editingText
        if let nsDoc = self.getNSDocument() {
            nsDoc.updateChangeCount(.changeDone)
        }
    }
    
    func snapshot(contentType: UTType) throws -> String {
        content
    }
    
    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = snapshot.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        
        return FileWrapper(regularFileWithContents: data)
    }
    
    // Add a computed property to access the URL in the ContentView
    var fileURL: URL? {
        // Access the underlying NSDocument to get the fileURL
        // This will be nil for new documents until they are saved
        let appDelegate = NSApp.delegate as? NSDocumentController
        if let currentDocument = appDelegate?.currentDocument as? NSDocument {
            return currentDocument.fileURL
        }
        return nil
    }
}
