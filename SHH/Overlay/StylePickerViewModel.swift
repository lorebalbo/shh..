import Combine
import Foundation
import SwiftData

/// A lightweight style descriptor for the picker UI, avoiding SwiftData threading issues.
struct StyleItem: Identifiable {
    let id: UUID
    let name: String
}

/// View model for the style picker popup. Manages the list of available styles
/// and the currently active style for the recording session.
final class StylePickerViewModel: ObservableObject, @unchecked Sendable {
    @Published var styles: [StyleItem] = []
    @Published var activeStyleId: UUID?

    /// Called when the user selects a style (or nil for "No Style").
    var onStyleSelected: ((UUID?) -> Void)?

    func selectStyle(id: UUID?) {
        activeStyleId = id
        onStyleSelected?(id)
    }

    /// Reloads the style list from the given model context. Must be called on the main thread.
    func reload(from context: ModelContext) {
        let descriptor = FetchDescriptor<Style>(sortBy: [SortDescriptor(\.name)])
        guard let allStyles = try? context.fetch(descriptor) else { return }
        styles = allStyles.map { StyleItem(id: $0.id, name: $0.name) }
        activeStyleId = allStyles.first(where: { $0.isActive })?.id
    }
}
