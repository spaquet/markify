import SwiftUI

enum FontSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var id: String { rawValue }

    var swiftUISize: Font.TextStyle {
        switch self {
        case .small: return .callout      // ~14pt
        case .medium: return .body        // ~17pt
        case .large: return .title3       // ~20pt
        }
    }
}
