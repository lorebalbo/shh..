import SwiftUI

struct PermissionDeniedView: View {
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permissions needed")
                .font(.inter(27, .semibold))
                .tracking(-0.54)
                .foregroundStyle(Graphite.text)
                .accessibilityAddTraits(.isHeader)
            Text("Shh.. needs these to hear you and to notice when you hold fn.")
                .font(.inter(14))
                .lineSpacing(4)
                .foregroundStyle(Graphite.text2)
                .padding(.top, 4)
                .padding(.bottom, 24)

            permissionRow(
                title: "Accessibility",
                description: "Required for global hotkey detection and auto-paste.",
                granted: permissionManager.accessibilityGranted,
                isFirst: true,
                action: { permissionManager.requestAccessibilityPermission() },
                settingsAction: { permissionManager.openAccessibilitySettings() }
            )

            permissionRow(
                title: "Microphone",
                description: "Required to capture voice dictation.",
                granted: permissionManager.microphoneGranted,
                action: {
                    Task { await permissionManager.requestMicrophonePermission() }
                },
                settingsAction: { permissionManager.openMicrophoneSettings() }
            )
        }
        .frame(width: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Graphite.background)
        .onAppear {
            permissionManager.refreshPermissions()
        }
    }

    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        isFirst: Bool = false,
        action: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) -> some View {
        SettingRow(title, description: description, isFirst: isFirst) {
            if granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    Text("Granted")
                }
                .font(.inter(12.5))
                .foregroundStyle(Graphite.text3)
            } else {
                Button("Open Settings", action: settingsAction)
                    .buttonStyle(.graphite(.plain))
                Button("Grant access", action: action)
                    .buttonStyle(.graphite(.primary))
            }
        }
    }
}
