import Foundation

/// The text the editor's clock key writes into a note.
///
/// A named function with a **required** locale rather than a `.formatted()` call at the call
/// site, because the two differ in exactly the way `check-l10n.sh` rule 7 is about:
/// `.formatted()` resolves against `Locale.current` — the *device's* language — so a note written
/// after the user picked another language in the app would be stamped in the wrong one. Passing
/// the environment's locale is not optional here; the signature makes forgetting it impossible.
///
/// What it deliberately does not do is stay live. The result is inserted into the body as the
/// user's own characters, and from that moment it is content: re-resolving it later would rewrite
/// what they wrote.
public enum NoteTimestamp {
    public static func text(at date: Date = Date(), locale: Locale) -> String {
        Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(locale)
            .format(date)
    }
}
