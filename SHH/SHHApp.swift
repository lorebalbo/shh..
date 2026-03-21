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
        MenuBarExtra("SHH", systemImage: "waveform") {
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

// MARK: - App Custom Colors
extension Color {
    static let appBackground = Color(hex: "F6F7EB")
    static let appForeground = Color(hex: "393E41")
    static let appError = Color(hex: "E94F37")
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
