import SwiftData
import SwiftUI

@main
struct SHHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var permissionManager = PermissionManager()

    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            DictationEntry.self,
            Style.self,
            LLMProviderConfig.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        appDelegate.modelContainer = modelContainer
    }

    var body: some Scene {
        MenuBarExtra("Shh..", systemImage: "waveform") {
            MenuBarView()
        }
        .modelContainer(modelContainer)

        Window("", id: "dashboard") {
            DashboardView()
                .environment(permissionManager)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 800, height: 550)
    }
}
