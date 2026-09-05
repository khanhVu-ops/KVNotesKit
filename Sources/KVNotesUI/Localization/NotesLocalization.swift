import Foundation

enum NotesLocalization {
    static let supportedLanguages = [
        "en", "ar", "zh-Hans", "zh-Hant", "nl", "fr", "de", "hi", "id", "it",
        "ja", "ko", "pt-BR", "pt-PT", "ru", "es", "th", "tr", "vi"
    ]

    static var bundle: Bundle { .module }

    static func resource(_ key: String) -> LocalizedStringResource {
        value(String.LocalizationValue(key))
    }

    /// The interpolating form, for the counted strings whose plural rules live in
    /// `Localizable.stringsdict`.
    ///
    /// Interpolation is what makes the count part of the key (`"\(n) notes"` looks up
    /// `%lld notes`) and hands the number to the plural rule. A number drawn as its own `Text`
    /// beside a fixed noun cannot do that: Russian needs three forms of "заметка" and Arabic
    /// six, and English's own "1 notes" is the same bug in a language nobody would ship it in.
    static func value(_ value: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(value, bundle: .atURL(Bundle.module.bundleURL))
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

    static func notesKit(count value: String.LocalizationValue) -> LocalizedStringResource {
        NotesLocalization.value(value)
    }
}
