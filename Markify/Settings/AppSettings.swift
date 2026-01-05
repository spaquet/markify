import SwiftUI

class AppSettings: ObservableObject {
    // MARK: - Auto-Save Settings
    @AppStorage("autoSaveEnabled") var autoSaveEnabled: Bool = true
    @AppStorage("autoSaveDelay") var autoSaveDelay: Double = 1.0 // seconds
    @AppStorage("showSaveNotifications") var showSaveNotifications: Bool = true
    @AppStorage("saveNotificationDuration") var saveNotificationDuration: Double = 2.0 // seconds

    // MARK: - Editor Settings
    @AppStorage("editorFontSize") var editorFontSize: String = FontSize.medium.rawValue
    @AppStorage("editorFontFamily") var editorFontFamily: String = FontFamily.monospaced.rawValue
    @AppStorage("showEditorOnLaunch") var showEditorOnLaunch: Bool = true

    // MARK: - Sidebar Settings
    @AppStorage("recentFilesCount") var recentFilesCount: Int = 5
    @AppStorage("showRecentFiles") var showRecentFiles: Bool = true

    // MARK: - Preview Settings
    @AppStorage("markdownTheme") var markdownTheme: String = MarkdownTheme.github.rawValue

    // MARK: - Computed Properties

    /// Auto-save delay in nanoseconds for Task.sleep
    var autoSaveDelayNanoseconds: UInt64 {
        autoSaveEnabled ? UInt64(autoSaveDelay * 1_000_000_000) : 0
    }

    /// Save notification duration in nanoseconds for Task.sleep
    var saveNotificationDurationNanoseconds: UInt64 {
        UInt64(saveNotificationDuration * 1_000_000_000)
    }

    /// SwiftUI Font based on selected size and family
    var editorFont: Font {
        let size = FontSize(rawValue: editorFontSize) ?? .medium
        let family = FontFamily(rawValue: editorFontFamily) ?? .monospaced

        switch family {
        case .system:
            return .system(size.swiftUISize)
        case .monospaced:
            return .system(size.swiftUISize, design: .monospaced)
        case .serif:
            return .system(size.swiftUISize, design: .serif)
        case .rounded:
            return .system(size.swiftUISize, design: .rounded)
        }
    }

    // MARK: - Singleton
    static let shared = AppSettings()

    private init() {}
}
