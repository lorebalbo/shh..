import AppKit
import SwiftUI

/// A minimal non-activating panel for content that needs SwiftUI interactivity.
/// Unlike OverlayPanel it does NOT intercept mouse events, so SwiftUI buttons
/// inside receive clicks normally.
private final class InteractiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages the style picker popup panel that appears above the overlay widget
/// when recording starts. Uses the same non-activating panel pattern as the
/// main overlay widget to avoid stealing focus.
/// Conforms to @unchecked Sendable because all mutations happen on the main thread.
final class StylePickerController: @unchecked Sendable {

    private let panel: InteractiveOverlayPanel
    private let hostingView: NSHostingView<StylePickerView>
    let viewModel: StylePickerViewModel

    /// Tracks whether a hide animation is in progress so that a subsequent
    /// show() call can cancel the stale orderOut completion.
    private var pendingHide = false

    private static let edgeGap: CGFloat = 4
    private static let screenMargin: CGFloat = 8

    init(viewModel: StylePickerViewModel) {
        self.viewModel = viewModel

        let contentRect = NSRect(
            origin: .zero,
            size: CGSize(
                width: StylePickerMetrics.width,
                height: StylePickerMetrics.panelHeight(styleCount: viewModel.styles.count)
            )
        )

        panel = InteractiveOverlayPanel(
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
        pendingHide = false // Cancel any in-flight hide completion
        applyFrame(relativeTo: widgetFrame)
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
        pendingHide = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.pendingHide else { return }
            self.pendingHide = false
            self.panel.orderOut(nil)
        })
    }

    /// Updates the picker position to track the widget if it moves.
    func updatePosition(relativeTo widgetFrame: NSRect) {
        applyFrame(relativeTo: widgetFrame)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    private func applyFrame(relativeTo widgetFrame: NSRect) {
        let nextFrame = panelFrame(relativeTo: widgetFrame)
        hostingView.frame = NSRect(origin: .zero, size: nextFrame.size)
        hostingView.needsLayout = true
        panel.setFrame(nextFrame, display: true)
    }

    private func panelFrame(relativeTo widgetFrame: NSRect) -> NSRect {
        let preferredSize = CGSize(
            width: StylePickerMetrics.width,
            height: StylePickerMetrics.panelHeight(styleCount: viewModel.styles.count)
        )

        guard let visibleFrame = screen(containing: widgetFrame)?.visibleFrame else {
            let origin = NSPoint(
                x: widgetFrame.midX - preferredSize.width / 2,
                y: widgetFrame.maxY + Self.edgeGap
            )
            return NSRect(origin: origin, size: preferredSize)
        }

        let availableAbove = max(
            visibleFrame.maxY - Self.screenMargin - widgetFrame.maxY - Self.edgeGap,
            0
        )
        let availableBelow = max(
            widgetFrame.minY - Self.edgeGap - visibleFrame.minY - Self.screenMargin,
            0
        )
        let placement: StylePickerPlacement = availableAbove >= preferredSize.height || availableAbove >= availableBelow
            ? .aboveWidget
            : .belowWidget

        if viewModel.placement != placement {
            viewModel.placement = placement
        }

        let availableHeight = placement == .aboveWidget ? availableAbove : availableBelow
        let panelHeight = min(
            preferredSize.height,
            max(availableHeight, StylePickerMetrics.minimumPanelHeight)
        )
        let panelSize = CGSize(width: preferredSize.width, height: panelHeight)

        let originX = Self.clamped(
            widgetFrame.midX - panelSize.width / 2,
            lowerBound: visibleFrame.minX + Self.screenMargin,
            upperBound: visibleFrame.maxX - panelSize.width - Self.screenMargin
        )
        let unclampedOriginY = placement == .aboveWidget
            ? widgetFrame.maxY + Self.edgeGap
            : widgetFrame.minY - Self.edgeGap - panelSize.height
        let originY = Self.clamped(
            unclampedOriginY,
            lowerBound: visibleFrame.minY + Self.screenMargin,
            upperBound: visibleFrame.maxY - panelSize.height - Self.screenMargin
        )

        return NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.visibleFrame.intersects(rect)
        } ?? NSScreen.main
    }

    private static func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        guard lowerBound <= upperBound else { return lowerBound }
        return min(max(value, lowerBound), upperBound)
    }
}
