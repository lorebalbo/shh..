import Foundation

/// Computes Word Error Rate (WER) via Levenshtein word-edit distance between a
/// normalized reference and hypothesis. WER = (S + D + I) / N where S, D, I are
/// substitutions, deletions and insertions and N is the reference word count.
///
/// Pure and deterministic — no whisper.cpp dependency — so it is unit tested
/// directly.
enum WERCalculator {
    /// The breakdown of a WER computation.
    struct Result: Equatable {
        let substitutions: Int
        let deletions: Int
        let insertions: Int
        let referenceWords: Int

        /// WER as a fraction. `nil` when the reference is empty (undefined).
        var wer: Double? {
            guard referenceWords > 0 else { return nil }
            return Double(substitutions + deletions + insertions) / Double(referenceWords)
        }
    }

    /// Computes WER between two pre-tokenized word lists.
    /// Policy: an empty reference yields `referenceWords == 0` and `wer == nil`.
    /// A non-empty reference with an empty hypothesis yields `wer == 1.0`
    /// (all words deleted).
    static func compute(reference: [String], hypothesis: [String]) -> Result {
        let refCount = reference.count
        let hypCount = hypothesis.count

        // Classic Levenshtein DP over words with full backtrace to classify
        // each edit as a substitution, deletion or insertion.
        var dp = Array(
            repeating: Array(repeating: 0, count: hypCount + 1),
            count: refCount + 1
        )
        for i in 0...refCount { dp[i][0] = i }
        for j in 0...hypCount { dp[0][j] = j }

        for i in 1...max(refCount, 1) where refCount > 0 {
            for j in 1...max(hypCount, 1) where hypCount > 0 {
                if reference[i - 1] == hypothesis[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    let substitution = dp[i - 1][j - 1] + 1
                    let deletion = dp[i - 1][j] + 1
                    let insertion = dp[i][j - 1] + 1
                    dp[i][j] = min(substitution, deletion, insertion)
                }
            }
        }

        // Backtrace from (refCount, hypCount) to count each edit type.
        var i = refCount
        var j = hypCount
        var substitutions = 0
        var deletions = 0
        var insertions = 0
        while i > 0 || j > 0 {
            if i > 0, j > 0, reference[i - 1] == hypothesis[j - 1], dp[i][j] == dp[i - 1][j - 1] {
                i -= 1; j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                substitutions += 1; i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                deletions += 1; i -= 1
            } else {
                insertions += 1; j -= 1
            }
        }

        return Result(
            substitutions: substitutions,
            deletions: deletions,
            insertions: insertions,
            referenceWords: refCount
        )
    }

    /// Convenience: normalizes both strings with `WhisperTextNormalizer` and
    /// computes WER on the resulting tokens.
    static func compute(referenceText: String, hypothesisText: String) -> Result {
        compute(
            reference: WhisperTextNormalizer.tokens(referenceText),
            hypothesis: WhisperTextNormalizer.tokens(hypothesisText)
        )
    }
}
