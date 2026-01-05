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
    @EnvironmentObject var settings: AppSettings
    @State private var showEditor = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var documentTitle: String = "Untitled"
    @State private var editorText: String = ""
    @State private var showSaveNotification = false
    @State private var saveNotificationTask: Task<Void, Never>?
    @State private var isInitializing = true

    var body: some View {
        NavigationSplitView {
            SidebarView(content: $document.content, document: document)
        } detail: {
            HStack(alignment: .top, spacing: 16) {
                if showEditor {
                    TextEditor(text: $editorText)
                        .font(settings.editorFont)
                        .padding(16)
                        .frame(minWidth: 300)
                        .background(Color(.windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: editorText) { oldValue, newValue in
                            // Skip auto-save during initial document load
                            if !isInitializing {
                                document.debouncedSave(from: newValue, settings: settings)
                            }
                        }
                }

                ScrollView {
                    // Configure markdown with proper image handling and selectable text
                    Markdown(document.content)
                        .markdownTheme(markdownThemeValue)
                        .textSelection(.enabled) // Make text selectable
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            .overlay(alignment: .top) {
                if showSaveNotification {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .shadow(radius: 2)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: saveDocument) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save (⌘S)")
                    .keyboardShortcut("s", modifiers: .command)

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
                editorText = document.editingContent
                showEditor = settings.showEditorOnLaunch
                // Mark initialization as complete to enable auto-save on user edits
                isInitializing = false
            }
            .onChange(of: document.fileURL) { oldValue, newValue in
                updateDocumentTitle()
            }
            .onChange(of: document.content) { oldValue, newValue in
                // Sync editor text when document content changes from sidebar
                if editorText != newValue {
                    editorText = newValue
                }
            }
            .onChange(of: document.didAutoSave) { oldValue, newValue in
                // Show notification when auto-save happens (if enabled)
                if settings.showSaveNotifications {
                    showSaveNotification(animated: true)
                }
            }
        }
    }

    private func saveDocument() {
        document.explicitSave(from: editorText)
        showSaveNotification(animated: true)
    }

    private func showSaveNotification(animated: Bool = true) {
        // Cancel any pending hide task
        saveNotificationTask?.cancel()

        withAnimation {
            showSaveNotification = true
        }

        // Schedule hiding after configured duration
        saveNotificationTask = Task {
            do {
                try await Task.sleep(nanoseconds: settings.saveNotificationDurationNanoseconds)
                if !Task.isCancelled {
                    withAnimation {
                        showSaveNotification = false
                    }
                }
            } catch {
                return
            }
        }
    }

    private var markdownThemeValue: MarkdownUI.Theme {
        MarkdownTheme(rawValue: settings.markdownTheme) == .github ? .gitHub : .basic
    }

    private func updateDocumentTitle() {
        if let url = document.fileURL {
            documentTitle = url.lastPathComponent
        } else {
            documentTitle = "Untitled"
        }
    }
}
