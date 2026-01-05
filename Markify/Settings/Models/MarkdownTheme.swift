import Foundation

enum MarkdownTheme: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case basic = "Basic"

    var id: String { rawValue }
}
