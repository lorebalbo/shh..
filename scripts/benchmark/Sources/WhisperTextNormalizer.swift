import Foundation

/// A Swift port of the OpenAI Whisper "English text normalizer" rules used to
/// compare a hypothesis transcript against a reference fairly. Normalization
/// removes superficial differences (casing, punctuation, spacing, contraction
/// spelling, digit vs. word) so WER reflects real recognition errors rather
/// than formatting.
///
/// Pure and deterministic — no whisper.cpp dependency — so it is unit tested
/// directly against a fixture set of input/expected pairs.
enum WhisperTextNormalizer {
    /// Normalizes a transcript to a canonical, space-separated token string.
    static func normalize(_ text: String) -> String {
        var working = text.lowercased()

        // 1. Expand common English contractions before punctuation stripping so
        //    the apostrophe is still present to anchor the match.
        working = expandContractions(working)

        // 2. Replace any character that is not a letter, digit or whitespace
        //    with a space (strips punctuation, symbols, quotes).
        working = working.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }.reduce(into: "") { $0.append($1) }

        // 3. Tokenize, mapping number words to digits where unambiguous.
        let tokens = working
            .split(whereSeparator: { $0.isWhitespace })
            .map { spellOutNumberIfPossible(String($0)) }

        // 4. Collapse whitespace by joining single-spaced.
        return tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Splits the normalized string into word tokens.
    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    // MARK: - Private

    private static func expandContractions(_ text: String) -> String {
        var result = text
        // Whole-word replacements first.
        for (key, value) in [
            "won't": "will not",
            "can't": "cannot",
            "let's": "let us",
            "it's": "it is",
            "i'm": "i am",
        ] {
            result = result.replacingOccurrences(of: key, with: value)
        }
        // Suffix replacements.
        for (key, value) in [
            "n't": " not",
            "'re": " are",
            "'ve": " have",
            "'ll": " will",
            "'d": " would",
            "'m": " am",
            "'s": "",
        ] {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    private static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19", "twenty": "20",
    ]

    private static func spellOutNumberIfPossible(_ token: String) -> String {
        numberWords[token] ?? token
    }
}
