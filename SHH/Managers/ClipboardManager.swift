import ApplicationServices
import AppKit
import CoreGraphics
import os.log

/// Manages the system clipboard for the auto-paste flow: saves a snapshot
/// of the current pasteboard contents, writes dictated text, simulates Cmd+V,
/// and restores the original clipboard after a short delay.
///
/// Requires Accessibility permission for CGEvent-based paste simulation.
@MainActor
final class ClipboardManager {
    /// Delay before restoring clipboard contents after paste (ADR Decision 6).
    private static let restoreDelayMs: Int = 300

    private let logger = Logger(subsystem: "com.shh.voice-utility", category: "ClipboardManager")

    /// A snapshot of a single pasteboard item: an ordered list of type-data pairs.
    struct PasteboardItemSnapshot {
        let entries: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    /// A full snapshot of all items on the general pasteboard.
    private var snapshot: [PasteboardItemSnapshot]?

    // MARK: - Snapshot Save & Restore

    /// Reads all items and their associated types from `NSPasteboard.general`
    /// into an in-memory snapshot.
    func saveClipboard() {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems else {
            snapshot = []
            return
        }

        var savedItems: [PasteboardItemSnapshot] = []
        for item in items {
            var entries: [(type: NSPasteboard.PasteboardType, data: Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    entries.append((type: type, data: data))
                }
            }
            if !entries.isEmpty {
                savedItems.append(PasteboardItemSnapshot(entries: entries))
            }
        }

        snapshot = savedItems
        logger.debug("Clipboard saved: \(savedItems.count) item(s)")
    }

    /// Clears the general pasteboard and writes the saved snapshot back.
    /// If the snapshot cannot be fully restored (e.g. complex types that
    /// don't round-trip), logs the issue silently and leaves the current
    /// clipboard content in place.
    func restoreClipboard() {
        guard let savedItems = snapshot else { return }
        snapshot = nil

        let pasteboard = NSPasteboard.general

        // Empty snapshot means the clipboard was empty — just clear it.
        guard !savedItems.isEmpty else {
            pasteboard.clearContents()
            logger.debug("Clipboard restored to empty state")
            return
        }

        pasteboard.clearContents()

        for itemSnapshot in savedItems {
            let pasteboardItem = NSPasteboardItem()
            var restoredAny = false

            for entry in itemSnapshot.entries {
                if pasteboardItem.setData(entry.data, forType: entry.type) {
                    restoredAny = true
                } else {
                    logger.info("Could not restore pasteboard type: \(entry.type.rawValue)")
                }
            }

            if restoredAny {
                pasteboard.writeObjects([pasteboardItem])
            }
        }

        logger.debug("Clipboard restored: \(savedItems.count) item(s)")
    }

    // MARK: - Auto-Paste

    /// Performs the full auto-paste flow:
    /// 1. Saves the current pasteboard content.
    /// 2. Writes `text` as a plain string to the general pasteboard.
    /// 3. Simulates Cmd+V via CGEvent to paste into the active app.
    /// 4. Schedules clipboard restoration after a 300ms delay.
    ///
    /// - Parameter text: The final dictated text (RAW or Processed) to paste.
    func autoPaste(text: String) {
        let accessibilityGranted = AXIsProcessTrusted()

        // Only save/restore clipboard if we can actually simulate Cmd+V
        if accessibilityGranted {
            saveClipboard()
        }

        // Write the dictated text to the pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if accessibilityGranted {
            // Simulate Cmd+V
            simulatePaste()

            // Schedule clipboard restoration after delay
            let delayMs = Self.restoreDelayMs
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
                self?.restoreClipboard()
            }
        } else {
            logger.info("Accessibility permission not granted — text left on clipboard for manual paste")
        }
    }

    // MARK: - CGEvent Paste Simulation

    /// Creates and posts CGEvent key-down and key-up events for 'V' (virtual
    /// key 0x09) with the Command flag to simulate Cmd+V.
    private func simulatePaste() {
        let vKeyCode: CGKeyCode = 0x09

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for Cmd+V simulation")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.debug("Simulated Cmd+V paste")
    }
}
