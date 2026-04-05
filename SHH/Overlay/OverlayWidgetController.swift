import AppKit
import SwiftUI

/// Custom NSPanel subclass that never becomes key or main window,
/// ensuring the user's active application retains focus (ADR Decision 8).
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages the always-on-top overlay widget displayed as a borderless,
/// translucent NSPanel. The panel floats above all windows and never
/// steals focus from the active application.
/// Conforms to @unchecked Sendable because all mutations happen on the main thread.
final class OverlayWidgetController: @unchecked Sendable {

    // MARK: - Constants

    static let widgetSize = CGSize(width: 88, height: 22)

    private enum UserDefaultsKey {
        static let positionX = "SHH_OverlayPositionX"
        static let positionY = "SHH_OverlayPositionY"
        static let edge = "SHH_OverlayEdge"
    }

    // MARK: - Properties

    private let panel: OverlayPanel
    private let hostingView: NSHostingView<OverlayContentView>
    private let viewModel: OverlayViewModel
    private var screenObserver: NSObjectProtocol?
    private var dragStartOrigin: NSPoint = .zero
    private var isDragStarted = false

    // MARK: - Init

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel

        let contentRect = NSRect(
            origin: .zero,
            size: Self.widgetSize
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
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        hostingView = NSHostingView(
            rootView: OverlayContentView(viewModel: viewModel)
        )
        hostingView.frame = contentRect
        panel.contentView = hostingView

        observeScreenChanges()
        setupDragHandling()
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public

    func show() {
        let origin = restoredPosition()
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Updates the panel's position externally (e.g., after a drag).
    func updatePosition(to origin: NSPoint) {
        panel.setFrameOrigin(origin)
        savePosition(origin)
    }

    /// Returns the panel's current frame origin.
    var currentOrigin: NSPoint {
        panel.frame.origin
    }

    /// Returns the panel reference for drag handling.
    var panelWindow: NSPanel {
        panel
    }

    // MARK: - Drag Handling

    private func setupDragHandling() {
        viewModel.onDragChanged = { [weak self] translation in
            guard let self else { return }
            if !self.isDragStarted {
                self.isDragStarted = true
                self.dragStartOrigin = self.panel.frame.origin
            }
            // SwiftUI global DragGesture Y is inverted relative to AppKit coordinates
            let newOrigin = NSPoint(
                x: self.dragStartOrigin.x + translation.width,
                y: self.dragStartOrigin.y - translation.height
            )
            self.panel.setFrameOrigin(newOrigin)
        }

        viewModel.onDragEnded = { [weak self] in
            guard let self else { return }
            let currentOrigin = self.panel.frame.origin
            let snapped = Self.snappedPosition(
                for: currentOrigin,
                widgetSize: Self.widgetSize
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrameOrigin(snapped)
            }
            self.savePosition(snapped)
            self.dragStartOrigin = .zero
            self.isDragStarted = false
        }
    }

    // MARK: - Position Persistence

    func savePosition(_ origin: NSPoint) {
        let edge = Self.nearestEdge(for: origin, widgetSize: Self.widgetSize)
        UserDefaults.standard.set(Double(origin.x), forKey: UserDefaultsKey.positionX)
        UserDefaults.standard.set(Double(origin.y), forKey: UserDefaultsKey.positionY)
        UserDefaults.standard.set(edge.rawValue, forKey: UserDefaultsKey.edge)
    }

    private func restoredPosition() -> NSPoint {
        let hasPosition = UserDefaults.standard.object(forKey: UserDefaultsKey.positionX) != nil

        guard hasPosition else {
            return Self.defaultBottomCenter()
        }

        let x = UserDefaults.standard.double(forKey: UserDefaultsKey.positionX)
        let y = UserDefaults.standard.double(forKey: UserDefaultsKey.positionY)
        let point = NSPoint(x: x, y: y)

        guard Self.isPositionOnScreen(point, widgetSize: Self.widgetSize) else {
            return Self.defaultBottomCenter()
        }

        return point
    }

    // MARK: - Edge Snapping

    enum ScreenEdge: String {
        case top, bottom, left, right
    }

    /// Snaps the given origin to the nearest screen edge.
    static func snappedPosition(
        for origin: NSPoint,
        widgetSize: CGSize,
        screen: NSScreen? = NSScreen.main
    ) -> NSPoint {
        guard let screen else {
            return origin
        }

        let visibleFrame = screen.visibleFrame
        let edge = nearestEdge(for: origin, widgetSize: widgetSize, screen: screen)
        return positionForEdge(edge, origin: origin, widgetSize: widgetSize, visibleFrame: visibleFrame)
    }

    static func nearestEdge(
        for origin: NSPoint,
        widgetSize: CGSize,
        screen: NSScreen? = NSScreen.main
    ) -> ScreenEdge {
        guard let screen else { return .bottom }

        let visibleFrame = screen.visibleFrame
        let centerX = origin.x + widgetSize.width / 2
        let centerY = origin.y + widgetSize.height / 2

        let distToLeft = centerX - visibleFrame.minX
        let distToRight = visibleFrame.maxX - centerX
        let distToBottom = centerY - visibleFrame.minY
        let distToTop = visibleFrame.maxY - centerY

        let minDist = min(distToLeft, distToRight, distToBottom, distToTop)

        if minDist == distToBottom { return .bottom }
        if minDist == distToTop { return .top }
        if minDist == distToLeft { return .left }
        return .right
    }

    private static func positionForEdge(
        _ edge: ScreenEdge,
        origin: NSPoint,
        widgetSize: CGSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let clampedX = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - widgetSize.width)
        let clampedY = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - widgetSize.height)

        switch edge {
        case .bottom:
            return NSPoint(x: clampedX, y: visibleFrame.minY)
        case .top:
            return NSPoint(x: clampedX, y: visibleFrame.maxY - widgetSize.height)
        case .left:
            return NSPoint(x: visibleFrame.minX, y: clampedY)
        case .right:
            return NSPoint(x: visibleFrame.maxX - widgetSize.width, y: clampedY)
        }
    }

    // MARK: - Screen Validation

    private static func isPositionOnScreen(_ point: NSPoint, widgetSize: CGSize) -> Bool {
        let widgetRect = NSRect(origin: point, size: widgetSize)
        return NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(widgetRect)
        }
    }

    static func defaultBottomCenter(screen: NSScreen? = NSScreen.main) -> NSPoint {
        guard let screen else {
            return .zero
        }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - widgetSize.width / 2
        let y = visibleFrame.minY
        return NSPoint(x: x, y: y)
    }

    // MARK: - Screen Change Observation

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    private func handleScreenChange() {
        let currentOrigin = panel.frame.origin
        if !Self.isPositionOnScreen(currentOrigin, widgetSize: Self.widgetSize) {
            let fallback = Self.defaultBottomCenter()
            panel.setFrameOrigin(fallback)
            savePosition(fallback)
        }
    }
}
