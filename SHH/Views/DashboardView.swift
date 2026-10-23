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
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 700, minHeight: 500)
        .background(Graphite.background)
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
            .background(Graphite.background)
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

private struct Sidebar: View {
    @Environment(DashboardModel.self) private var dashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dashboard.page = .home
            } label: {
                Text("Shh..")
                    .font(.inter(15, .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Graphite.text)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .padding(.top, 46)

            VStack(spacing: 2) {
                NavRow(page: .home)
                NavRow(page: .styles)
                Spacer().frame(height: 16)
                NavRow(page: .speech)
                NavRow(page: .providers)
            }
            .padding(.top, 20)

            Spacer(minLength: 16)

            VStack(spacing: 2) {
                NavRow(page: .settings)
                NavRow(page: .help)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Graphite.sidebar)
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
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Graphite.accent : isHovered ? Graphite.text2 : Graphite.text3)
                Text(page.title)
                    .font(.inter(13.5, isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected || isHovered ? Graphite.text : Graphite.text2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isSelected ? Graphite.selected : isHovered ? Graphite.hover : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Toast

private struct ToastHost: View {
    @Environment(DashboardModel.self) private var dashboard

    var body: some View {
        if let toast = dashboard.toast {
            HStack(spacing: 10) {
                toast.message
                    .font(.inter(14))
                    .foregroundStyle(Graphite.text)
                if toast.undo != nil {
                    Button("Undo") { dashboard.undoToast() }
                        .buttonStyle(.graphite(.plain))
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, toast.undo == nil ? 14 : 6)
            .padding(.vertical, toast.undo == nil ? 9 : 6)
            .background(Graphite.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 18, y: 14)
            .padding(.bottom, 22)
            .id(toast.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}
