import Foundation
import Observation

struct PipelineEvent: Identifiable {
    let id = UUID()
    let timestamp: Date = .now
    let message: String
    let kind: Kind

    enum Kind {
        case info, success, error
    }
}

@Observable
final class PipelineEventLog: @unchecked Sendable {
    nonisolated(unsafe) static let shared = PipelineEventLog()
    private init() {}

    private(set) var events: [PipelineEvent] = []

    /// Thread-safe append — can be called from any thread.
    func append(_ message: String, kind: PipelineEvent.Kind = .info) {
        let event = PipelineEvent(message: message, kind: kind)
        if Thread.isMainThread {
            insertEvent(event)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.insertEvent(event)
            }
        }
    }

    func clear() {
        events.removeAll()
    }

    private func insertEvent(_ event: PipelineEvent) {
        events.insert(event, at: 0)
        if events.count > 40 {
            events = Array(events.prefix(40))
        }
    }
}
