import Foundation
import SwiftData

@Model
final class DictationEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rawText: String
    var processedText: String?
    var styleId: UUID?
    var audioFilePath: String?

    init(rawText: String, processedText: String? = nil, styleId: UUID? = nil, audioFilePath: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawText = rawText
        self.processedText = processedText
        self.styleId = styleId
        self.audioFilePath = audioFilePath
    }
}

extension DictationEntry {
    /// rawText stored for recordings that produced no transcript.
    static let noSpeechText = "(no speech detected)"
    static let transcriptionErrorText = "(transcription error)"

    /// What pasting this dictation inserts: the style's rewrite if one was applied,
    /// otherwise the transcript. nil for recordings that produced no transcript.
    var pastableText: String? {
        if let processedText { return processedText }
        return rawText == Self.noSpeechText || rawText == Self.transcriptionErrorText ? nil : rawText
    }

    /// The most recent dictation that has text to paste.
    static func lastPastableText(in context: ModelContext) -> String? {
        let noSpeech = noSpeechText
        let transcriptionError = transcriptionErrorText
        var descriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate { $0.rawText != noSpeech && $0.rawText != transcriptionError },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.pastableText
    }
}
