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

class MarkifyDocument: ReferenceFileDocument {
    @Published var content: String = ""
    
    // Store the fileURL as a property but don't try to set it directly
    // ReferenceFileDocument will handle the file URL internally
    
    static var readableContentTypes: [UTType] {
        [.markdown, .mdx]
    }
    
    static var writableContentTypes: [UTType] {
        [.markdown, .mdx]
    }
    
    init() {
        content = ""
    }
    
    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = string
        // Don't try to set fileURL here - it's handled by the system
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
