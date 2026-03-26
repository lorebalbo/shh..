import AppKit
import SwiftUI

/// Manages the style picker popup panel that appears above the overlay widget
/// when recording starts. Uses the same non-activating panel pattern as the
/// main overlay widget to avoid stealing focus.
/// Conforms to @unchecked Sendable because all mutations happen on the main thread.
final class StylePickerController: @unchecked Sendable {

    private let panel: OverlayPanel
    private let hostingView: NSHostingView<StylePickerView>
    let viewModel: StylePickerViewModel

    /// The intrinsic size of the picker content.
    private static let pickerWidth: CGFloat = 180
    /// Estimated row height × max visible styles + padding. Actual height determined by content.
    private static let estimatedMaxHeight: CGFloat = 300

    init(viewModel: StylePickerViewModel) {
        self.viewModel = viewModel

        let contentRect = NSRect(
            origin: .zero,
            size: CGSize(width: Self.pickerWidth, height: Self.estimatedMaxHeight)
        )

        panel = OverlayPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // The SwiftUI view handles its own shadow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let pickerView = StylePickerView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: pickerView)
        hostingView.frame = contentRect
        panel.contentView = hostingView
    }

    /// Shows the picker above (or below) the given widget origin point.
    func show(relativeTo widgetFrame: NSRect) {
        // Size the hosting view to its intrinsic content size
        let fittingSize = hostingView.fittingSize
        let panelSize = CGSize(
            width: max(fittingSize.width, Self.pickerWidth),
            height: fittingSize.height
        )

        // Position above the widget, centered horizontally
        let x = widgetFrame.midX - panelSize.width / 2
        // 6pt gap between widget top and picker bottom (the tail bridges the gap visually)
        let y = widgetFrame.maxY + 4

        let origin = NSPoint(x: x, y: y)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Hides the picker with a fade-out animation.
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    /// Updates the picker position to track the widget if it moves.
    func updatePosition(relativeTo widgetFrame: NSRect) {
        let fittingSize = hostingView.fittingSize
        let panelSize = CGSize(
            width: max(fittingSize.width, Self.pickerWidth),
            height: fittingSize.height
        )
        let x = widgetFrame.midX - panelSize.width / 2
        let y = widgetFrame.maxY + 4
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: true)
    }

    var isVisible: Bool {
        panel.isVisible
    }
}
