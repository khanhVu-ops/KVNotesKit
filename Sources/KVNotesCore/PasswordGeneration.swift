import Foundation

/// What the user asked the generator for.
public struct PasswordRecipe: Equatable, Sendable {
    public static let lengthRange = 8...64

    public var length: Int
    public var includesDigits: Bool
    public var includesSymbols: Bool

    public init(length: Int = 20, includesDigits: Bool = true, includesSymbols: Bool = true) {
        self.length = min(max(length, Self.lengthRange.lowerBound), Self.lengthRange.upperBound)
        self.includesDigits = includesDigits
        self.includesSymbols = includesSymbols
    }
}

/// Generates a password from the system's cryptographic random source.
///
/// Every character is drawn independently from the alphabet, and the guaranteed one-per-class
/// characters are placed at random positions rather than shuffled into place: a shuffle of a
/// fixed character array is the classic way to end up with a password whose entropy is the
/// entropy of the shuffle, not of the alphabet.
///
/// The value is returned to the caller and inserted at the caret. It never goes through the
/// pasteboard — a generator that "helpfully" copies the password has just published it to every
/// app on the device, and to the handoff clipboard of every other device signed into the account.
public enum PasswordGeneration {
    public static let letters = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ")
    public static let digits = Array("23456789")
    public static let symbols = Array("!@#$%^&*()-_=+[]{};:,.?/")

    public static func password(
        for recipe: PasswordRecipe,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        var classes: [[Character]] = [letters]
        if recipe.includesDigits { classes.append(digits) }
        if recipe.includesSymbols { classes.append(symbols) }
        let alphabet = classes.flatMap { $0 }

        var characters = (0..<recipe.length).map { _ in
            alphabet.randomElement(using: &generator) ?? "x"
        }
        // One from each requested class, at positions drawn from the same source. Skipped when
        // the password is shorter than the number of classes, which the length range prevents.
        guard recipe.length >= classes.count else { return String(characters) }
        var positions = Array(characters.indices)
        for characterClass in classes {
            guard let slot = positions.indices.randomElement(using: &generator),
                  let character = characterClass.randomElement(using: &generator)
            else { continue }
            characters[positions.remove(at: slot)] = character
        }
        return String(characters)
    }

    public static func password(for recipe: PasswordRecipe) -> String {
        var generator = SystemRandomNumberGenerator()
        return password(for: recipe, using: &generator)
    }
}
