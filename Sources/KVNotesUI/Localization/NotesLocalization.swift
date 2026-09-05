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
}

extension LocalizedStringResource {
    static func notesKit(_ key: String) -> LocalizedStringResource {
        NotesLocalization.resource(key)
    }
}
