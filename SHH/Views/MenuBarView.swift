import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button("Open Dashboard") {
            openWindow(id: "dashboard")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("d")

        Divider()

        Toggle("Launch at Login", isOn: $launchAtLogin)
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

        Button("Quit SHH") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
