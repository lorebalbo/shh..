import Foundation
import SwiftData

@Model
final class Style {
    @Attribute(.unique) var id: UUID
    var name: String
    var systemPrompt: String
    var isActive: Bool

    init(name: String, systemPrompt: String, isActive: Bool = false) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.isActive = isActive
    }

    /// Activates this style, deactivating all others to enforce
    /// the single-active-style invariant.
    func activate(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Style>(
            predicate: #Predicate<Style> { $0.isActive }
        )
        let activeStyles = try context.fetch(descriptor)
        for style in activeStyles {
            style.isActive = false
        }
        self.isActive = true
    }
}

extension Notification.Name {
    static let shhStylesDidChange = Notification.Name("shhStylesDidChange")
}
