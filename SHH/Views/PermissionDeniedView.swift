import SwiftUI

struct PermissionDeniedView: View {
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.custom("League Spartan", size: 42))
                .foregroundStyle(.secondary)

            Text("Permissions Required")
                .font(Font.appTitle2)
                .fontWeight(.semibold)

            Text("SHH needs the following permissions to function correctly.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                permissionRow(
                    title: "Accessibility",
                    description: "Required for global hotkey detection and auto-paste.",
                    granted: permissionManager.accessibilityGranted,
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
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(32)
        .frame(width: 480)
        .onAppear {
            permissionManager.refreshPermissions()
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(Font.appTitle3)
                .foregroundStyle(granted ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(Font.appCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button("Grant Access") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Open Settings") {
                    settingsAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
