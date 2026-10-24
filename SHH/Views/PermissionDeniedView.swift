import SwiftUI

struct PermissionDeniedView: View {
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisplayText("Permissions needed", size: 40, stroke: 1.1, lineHeight: 1.05)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
            Text("Shh.. needs these to hear you and to notice when you hold fn.")
                .font(.sans(14))
                .lineSpacing(4)
                .foregroundStyle(Ink.text2)
                .padding(.top, 12)
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
        .frame(width: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper)
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
                .font(.sans(12.5, .semibold))
                .foregroundStyle(Ink.text)
            } else {
                Button("Open Settings", action: settingsAction)
                    .buttonStyle(.ink(.plain))
                Button("Grant access", action: action)
                    .buttonStyle(.ink(.primary))
            }
        }
    }
}
