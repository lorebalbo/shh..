import Foundation

/// Pure, deterministic reassembly of per-chunk Whisper transcripts into one
/// final string. Joins pieces with a single space, trims each piece, drops
/// empty pieces, and collapses the doubled whitespace and doubled terminal
/// punctuation that can appear where two chunks meet.
///
/// Free of any whisper.cpp dependency so it can be unit tested directly.
enum TranscriptStitcher {
    /// Stitches ordered per-chunk transcripts into a single transcript.
    static func stitch(_ pieces: [String]) -> String {
        let trimmed = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmed.isEmpty else { return "" }

        let joined = trimmed.joined(separator: " ")
        return collapsePunctuation(collapseWhitespace(joined))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    /// Collapses any run of whitespace into a single space.
    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
    }

    /// Collapses a run of terminal punctuation marks (optionally separated by
    /// spaces) into the first mark, e.g. ". ." or ".." becomes ".".
    private static func collapsePunctuation(_ text: String) -> String {
        text.replacingOccurrences(
            of: "([.!?,;:])(\\s*[.!?,;:])+",
            with: "$1",
            options: .regularExpression
        )
    }
}
