import Foundation

/// Localized string lookup. Strings live in `<lang>.lproj/Localizable.strings`
/// (uk = default/development region, plus ru and en). The active language follows
/// the device's language settings.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
