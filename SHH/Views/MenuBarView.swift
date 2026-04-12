import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button("Open Dashboard") {
            NotificationCenter.default.post(name: .openDashboardWindow, object: nil)
        }

        Divider()

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .tint(Color.appError)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Revert the toggle on failure
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()

        Button("Quit Shh..") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
