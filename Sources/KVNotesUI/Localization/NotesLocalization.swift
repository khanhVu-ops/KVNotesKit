import Foundation

enum NotesLocalization {
    static let supportedLanguages = [
        "en", "ar", "zh-Hans", "zh-Hant", "nl", "fr", "de", "hi", "id", "it",
        "ja", "ko", "pt-BR", "pt-PT", "ru", "es", "th", "tr", "vi"
    ]

    static var bundle: Bundle { .module }

    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(key),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// UIKit controls cannot carry a `LocalizedStringResource`, so resolve their title from the
    /// package table using the locale SwiftUI currently supplies.
    static func string(_ key: String, locale: Locale) -> String {
        let requested = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let language = supportedLanguages.first { requested.caseInsensitiveCompare($0) == .orderedSame }
            ?? supportedLanguages.first { requested.lowercased().hasPrefix($0.lowercased() + "-") }
            ?? "en"
        let bundle = Bundle.module.path(forResource: language, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .module
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

extension LocalizedStringResource {
    static func notesKit(_ key: String) -> LocalizedStringResource {
        NotesLocalization.resource(key)
    }
}
