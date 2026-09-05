import Foundation

/// Finds every occurrence of a query inside one note.
///
/// Returns ranges in the note's own text, in UTF-16 units, so the editor can highlight and scroll
/// to them without converting anything.
public enum NoteFind {
    /// A note long enough to exceed this has a query too broad to be useful — the count stops
    /// being information and the highlighting stops being a hint. Bounded so a single character
    /// typed into the find field cannot cost a frame in a very long note.
    public static let matchLimit = 500

    public static func matches(of query: String, in text: NSString) -> [NSRange] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.length > 0 else { return [] }

        // `Đ` is the reason this is not one call to `range(of:options:)`. Foundation's
        // diacritic-insensitive search does not fold it to `D` — measured — so "duong" would not
        // find "Đường", which is the search a Vietnamese user actually types. The substitution is
        // one UTF-16 unit for one, so every range found in the folded copy is also a range in the
        // original; anything that changed the length would put the highlight on the wrong words.
        let haystack = fold(text)
        let needle = fold(trimmed as NSString) as NSString
        guard needle.length > 0 else { return [] }

        var found: [NSRange] = []
        var searchStart = 0
        while searchStart < haystack.length, found.count < matchLimit {
            let remaining = NSRange(location: searchStart, length: haystack.length - searchStart)
            let match = haystack.range(
                of: needle as String,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: remaining
            )
            guard match.location != NSNotFound, match.length > 0 else { break }
            found.append(match)
            searchStart = match.location + match.length
        }
        return found
    }

    /// The index of the first match at or after `caret`, so opening find from where the user is
    /// reading does not throw them back to the top of the note.
    public static func indexOfMatch(at caret: Int, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.firstIndex { $0.location >= caret } ?? 0
    }

    private static func fold(_ text: NSString) -> NSString {
        let mutable = NSMutableString(string: text)
        mutable.replaceOccurrences(of: "đ", with: "d", options: [], range: NSRange(location: 0, length: mutable.length))
        mutable.replaceOccurrences(of: "Đ", with: "D", options: [], range: NSRange(location: 0, length: mutable.length))
        return mutable
    }
}
