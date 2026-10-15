import Foundation

extension String {
    /// A value stored in English, such as a setting choice, block style or accent name, in the user's language.
    /// The stored value never changes; no literal names these at the display site, so Localizable.xcstrings
    /// keeps them as manual entries.
    var localizedLabel: String { String(localized: LocalizationValue(self)) }
}
