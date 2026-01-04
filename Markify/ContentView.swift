//
//  ContentView.swift
//  Markify
//
//  Created by Stéphane PAQUET on 5/5/25.
//

import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @ObservedObject var document: MarkifyDocument
    @State private var showEditor = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var documentTitle: String = "Untitled"
    
    var body: some View {
        NavigationSplitView {
            SidebarView(content: $document.content, document: document)
        } detail: {
            HStack(alignment: .top, spacing: 16) {
                if showEditor {
                    TextEditor(text: $document.content)
                        .font(.system(.body, design: .monospaced))
                        .padding(16)
                        .frame(minWidth: 300)
                        .background(Color(.windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                ScrollView {
                    // Configure markdown with proper image handling and selectable text
                    Markdown(document.content)
                        .markdownTheme(.gitHub)
                        // Use the imageBaseURL parameter instead of a custom provider
                        .textSelection(.enabled) // Make text selectable
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            .toolbar {
                ToolbarItem {
                    Button(action: { showEditor.toggle() }) {
                        Image(systemName: showEditor ? "eye.slash" : "eye")
                    }
                    .help(showEditor ? "Hide Editor" : "Show Editor")
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
            .onChange(of: document.fileURL) { oldValue, newValue in
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
}
