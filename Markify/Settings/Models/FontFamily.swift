import Foundation

enum FontFamily: String, CaseIterable, Identifiable {
    case system = "System"
    case monospaced = "Monospaced"
    case serif = "Serif"
    case rounded = "Rounded"

    var id: String { rawValue }
}
