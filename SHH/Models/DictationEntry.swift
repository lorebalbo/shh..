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
