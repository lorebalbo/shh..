import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        Group {
            if permissionManager.allPermissionsGranted {
                DashboardContentView()
            } else {
                PermissionDeniedView()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            permissionManager.refreshPermissions()
        }
    }
}

// MARK: - Sidebar Navigation

enum SidebarSection: String, CaseIterable, Identifiable {
    case home
    case style
    case settings
    case help

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .style: "Style"
        case .settings: "Settings"
        case .help: "Help"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .style: "paintbrush"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        }
    }
}

private struct DashboardContentView: View {
    @State private var selectedSection: SidebarSection? = .home
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var showOnboarding = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selectedSection, collapsed: $sidebarCollapsed)
            
            Divider()
            
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 400)
                .background(Color.appBackground)
        }
        .background(Color.appBackground)
        .onAppear {
            if !hasCompletedSetup {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet(
                onGoToSettings: {
                    showOnboarding = false
                    hasCompletedSetup = true
                    selectedSection = .settings
                },
                onGoToStyles: {
                    showOnboarding = false
                    hasCompletedSetup = true
                    selectedSection = .style
                },
                onDismiss: {
                    showOnboarding = false
                    hasCompletedSetup = true
                }
            )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .home:
            HomeView()
        case .style:
            StyleView()
        case .settings:
            SettingsView()
        case .help:
            HelpView()
        case nil:
            HomeView()
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: SidebarSection?
    @Binding var collapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header: Logo & Title + Collapse Toggle
            ZStack {
                if !collapsed {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(Font.appTitle2)
                            .frame(width: 24, alignment: .center)
                        Text("Shh...")
                            .font(Font.appTitle3)
                            .fontWeight(.bold)
                            .fixedSize()
                    }
                    .foregroundStyle(Color.appForeground)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
                
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            collapsed.toggle()
                        }
                    } label: {
                        Image(systemName: collapsed ? "sidebar.right" : "sidebar.left")
                            .font(Font.appTitle2)
                            .foregroundStyle(Color.appForeground.opacity(0.8))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                }
            }
            .frame(height: 52)
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach([SidebarSection.home, SidebarSection.style]) { section in
                    SidebarRow(section: section, isSelected: selection == section, isCollapsed: collapsed) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach([SidebarSection.settings, SidebarSection.help]) { section in
                    SidebarRow(section: section, isSelected: selection == section, isCollapsed: collapsed) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .frame(width: collapsed ? 64 : 180)
        .background(Color.appBackground)
    }
}

private struct SidebarRow: View {
    let section: SidebarSection
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(Font.appTitle3) // Ensure smaller icon size
                    .frame(width: 24, alignment: .center)
                
                Text(section.label)
                    .font(Font.appBody)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(width: isCollapsed ? 44 : 160, alignment: .leading)
            .contentShape(Rectangle())
            .clipped() // Fixed icon centering with smooth collapse!
            .background(isSelected ? Color.appForeground.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.appError : Color.appForeground.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? section.label : "")
    }
}

// MARK: - Help View

struct HelpView: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    gettingStartedSection
                    keyboardShortcutsSection
                    aboutSection
                }
                .padding(24)
            }
        }
        .background(Color.appBackground)
    }

    private var header: some View {
        HStack {
            Text("Help")
                .font(Font.appLargeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Getting Started", systemImage: "play.circle")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)
            VStack(alignment: .leading, spacing: 8) {
                helpRow(icon: "mic", text: "Press the Fn key to start recording your voice.")
                helpRow(icon: "doc.on.clipboard", text: "Transcribed text is automatically copied to your clipboard.")
                helpRow(icon: "paintbrush", text: "Create Styles to transform your dictation with AI.")
                helpRow(icon: "gearshape", text: "Configure an LLM provider in Settings to enable Styles.")
            }
        }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
    }

    private var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow(key: "Fn", description: "Hold to record, release to transcribe")
                shortcutRow(key: "Cmd+D", description: "Open Dashboard from menu bar")
                shortcutRow(key: "Cmd+Q", description: "Quit SHH")
            }
        }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("About", systemImage: "info.circle")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)
            Text("SHH is a macOS voice utility that transcribes speech using on-device Whisper models and optionally processes text through AI styles.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
    }

    private func helpRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.tint)
            Text(text)
        }
    }

    private func shortcutRow(key: String, description: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.custom("League Spartan", size: 17).monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Onboarding Sheet

private struct OnboardingSheet: View {
    let onGoToSettings: () -> Void
    let onGoToStyles: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(.custom("League Spartan", size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to SHH")
                .font(Font.appTitle)
                .fontWeight(.bold)

            Text("Get started by setting up your voice utility in a few quick steps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                onboardingStep(
                    number: 1,
                    title: "Configure an LLM Provider",
                    description: "Add an API key for Anthropic, OpenAI, or set up a local endpoint to enable AI-powered text processing."
                )

                onboardingStep(
                    number: 2,
                    title: "Create a Style (Optional)",
                    description: "Styles transform your dictated text using AI. Create one to reformat, translate, or summarize your speech."
                )

                onboardingStep(
                    number: 3,
                    title: "Start Dictating",
                    description: "Press the Fn key to record. Your text will be transcribed and optionally processed."
                )
            }
            .padding(.vertical, 8)

            VStack(spacing: 8) {
                Button(action: onGoToSettings) {
                    Text("Go to Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onGoToStyles) {
                    Text("Create a Style")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Skip for Now", action: onDismiss)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(width: 420)
    }

    private func onboardingStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Font.appCaption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.tint)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(Font.appCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
