import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}
