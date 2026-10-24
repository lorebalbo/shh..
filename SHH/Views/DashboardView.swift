import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @State private var dashboard = DashboardModel()

    var body: some View {
        Group {
            if permissionManager.allPermissionsGranted {
                DashboardShell()
            } else {
                PermissionDeniedView()
            }
        }
        .environment(dashboard)
        .frame(minWidth: 700, minHeight: 500)
        .background(Ink.paper)
        .ignoresSafeArea()
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            permissionManager.refreshPermissions()
        }
    }
}

// MARK: - Navigation

enum DashboardPage: String, CaseIterable, Identifiable {
    case home
    case styles
    case speech
    case providers
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .styles: "Styles"
        case .speech: "Speech models"
        case .providers: "Providers"
        case .settings: "Settings"
        case .help: "Help"
        }
    }

    var subtitle: String {
        switch self {
        case .home: "Hold fn to dictate. Release, and it's on your clipboard."
        case .styles: "A style rewrites what you said before it's copied. Pick one, or none."
        case .speech: "Speech becomes text on this Mac and is never uploaded. Larger models are more accurate, but slower."
        case .providers: "When a style is on, the active provider does the rewriting. One at a time."
        case .settings: "How Shh.. starts, listens and what it keeps."
        case .help: "The basics and every shortcut."
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .styles: "paintbrush"
        case .speech: "waveform"
        case .providers: "powerplug"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        }
    }
}

/// Dashboard-wide UI state: the open page, the toast, and requests that cross pages
/// (⌘F focuses Home's search, ⌘N opens the Styles editor).
@Observable
@MainActor
final class DashboardModel {
    var page: DashboardPage = .home
    var wantsSearchFocus = false
    var wantsNewStyle = false
    private(set) var toast: Toast?
    private var toastTask: Task<Void, Never>?

    struct Toast: Identifiable {
        let id = UUID()
        let message: Text
        let undo: (@MainActor () -> Void)?
    }

    func focusSearch() {
        page = .home
        wantsSearchFocus = true
    }

    func newStyle() {
        page = .styles
        wantsNewStyle = true
    }

    /// Shows a short message at the bottom of the window. With `undo` it also offers
    /// Undo, and stays a little longer.
    func showToast(_ message: Text, undo: (@MainActor () -> Void)? = nil) {
        let toast = Toast(message: message, undo: undo)
        let id = toast.id
        withAnimation(.easeOut(duration: 0.18)) { self.toast = toast }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 3.5 : 5))
            guard !Task.isCancelled else { return }
            self?.dismissToast(id)
        }
    }

    func undoToast() {
        guard let toast, let undo = toast.undo else { return }
        dismissToast(toast.id)
        undo()
    }

    private func dismissToast(_ id: UUID) {
        guard toast?.id == id else { return }
        withAnimation(.easeOut(duration: 0.18)) { toast = nil }
    }
}

// MARK: - Shell

struct DashboardShell: View {
    @Environment(DashboardModel.self) private var dashboard
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ZStack(alignment: .bottom) {
                currentPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ToastHost()
            }
            .background(Ink.paper)
        }
        .background { shortcuts }
        .onAppear {
            // First run opens on Help's "Getting started" instead of an empty history.
            if !hasCompletedSetup {
                hasCompletedSetup = true
                dashboard.page = .help
            }
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch dashboard.page {
        case .home: HomeView()
        case .styles: StylesView()
        case .speech: SpeechModelsView()
        case .providers: LLMProvidersView()
        case .settings: SettingsView()
        case .help: HelpView()
        }
    }

    /// Window-wide shortcuts, carried by invisible buttons.
    private var shortcuts: some View {
        ZStack {
            Button("Search dictations") { dashboard.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("New style") { dashboard.newStyle() }
                .keyboardShortcut("n", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Sidebar

/// One ink blob. The current page is a paper tab that reaches out of the page into it.
private struct Sidebar: View {
    @Environment(DashboardModel.self) private var dashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dashboard.page = .home
            } label: {
                HStack(spacing: 10) {
                    InkMarkView(spraysOnHover: true)
                        .frame(width: 34, height: 39)
                    DisplayText("Shh..", size: 25, stroke: 0.8, lineHeight: 1, tracking: 0.02)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Ink.onInk)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.top, 44)
            .accessibilityLabel("Shh.. home")

            VStack(spacing: 3) {
                NavRow(page: .home)
                NavRow(page: .styles)
                Spacer().frame(height: 18)
                NavRow(page: .speech)
                NavRow(page: .providers)
            }
            .padding(.top, 24)

            Spacer(minLength: 16)

            VStack(spacing: 3) {
                NavRow(page: .settings)
                NavRow(page: .help)
            }
        }
        .padding(.leading, 12)
        // Room under the last tab for its lower corner before the blob curves away.
        .padding(.bottom, 48)
        .frame(width: 196)
        .frame(maxHeight: .infinity, alignment: .top)
        .backgroundPreferenceValue(NavRowFrames.self) { frames in
            GeometryReader { geometry in
                if let anchor = frames[dashboard.page] {
                    PageTab(frame: geometry[anchor], sidebarWidth: geometry.size.width, page: dashboard.page)
                }
            }
        }
        .background(Ink.ink, in: UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous))
    }
}

/// Where each nav row sits, so the tab can find the current one.
private struct NavRowFrames: PreferenceKey {
    static let defaultValue: [DashboardPage: Anchor<CGRect>] = [:]

    static func reduce(value: inout [DashboardPage: Anchor<CGRect>], nextValue: () -> [DashboardPage: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Slides to the current row with a little overshoot, and shortens as it travels, like a drop
/// pulled along the blob's edge.
private struct PageTab: View {
    let frame: CGRect
    let sidebarWidth: CGFloat
    let page: DashboardPage

    var body: some View {
        LiquidTab()
            .fill(Ink.paper)
            .frame(width: sidebarWidth - frame.minX, height: frame.height)
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: page) { tab, scale in
                tab.scaleEffect(scale, anchor: .trailing)
            } keyframes: { _ in
                CubicKeyframe(CGSize(width: 0.72, height: 0.82), duration: 0.16)
                CubicKeyframe(CGSize(width: 1, height: 1), duration: 0.29)
            }
            .offset(x: frame.minX, y: frame.minY)
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: frame)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NavRow: View {
    let page: DashboardPage
    @Environment(DashboardModel.self) private var dashboard
    @State private var isHovered = false

    var body: some View {
        let isSelected = dashboard.page == page
        Button {
            dashboard.page = page
        } label: {
            HStack(spacing: 11) {
                Image(systemName: page.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(page.title)
                    .font(.sans(14, isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Ink.ink : isHovered ? Ink.onInk : Ink.onInk2)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(!isSelected && isHovered ? Ink.inkHover : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .anchorPreference(key: NavRowFrames.self, value: .bounds) { [page: $0] }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Toast

/// An ink pill at the bottom of the page.
private struct ToastHost: View {
    @Environment(DashboardModel.self) private var dashboard

    var body: some View {
        if let toast = dashboard.toast {
            HStack(spacing: 12) {
                toast.message
                    .font(.sans(14, .medium))
                    .foregroundStyle(Ink.onInk)
                if toast.undo != nil {
                    Button("Undo") { dashboard.undoToast() }
                        .font(.sans(13.5, .semibold))
                        .foregroundStyle(Ink.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Ink.paper, in: Capsule())
                        .contentShape(Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, toast.undo == nil ? 18 : 6)
            .padding(.vertical, toast.undo == nil ? 9 : 6)
            .background(Ink.ink, in: Capsule())
            .shadow(color: Ink.shadow, radius: 20, y: 14)
            .padding(.bottom, 22)
            .id(toast.id)
            .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 10)))
            .accessibilityElement(children: .contain)
        }
    }
}
