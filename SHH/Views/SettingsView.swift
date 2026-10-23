import ServiceManagement
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DictationEntry]
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "auto"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isConfirmingClear = false

    private var count: Int { entries.count }
    private var dictations: String { count == 1 ? "1 dictation" : "\(count) dictations" }

    private var currentLanguageLabel: String {
        if transcriptionLanguage == "auto" { return "Auto-detect" }
        return TranscriptionLanguage.all.first { $0.code == transcriptionLanguage }?.name ?? transcriptionLanguage
    }

    var body: some View {
        PageScaffold(.settings) {
            VStack(alignment: .leading, spacing: 40) {
                SettingsGroup("Transcription") {
                    SettingRow(
                        "Language",
                        description: "Auto-detect works for most speech. Pin a language if it guesses wrong.",
                        isFirst: true
                    ) {
                        GraphiteMenu(currentLanguageLabel, width: 168) {
                            Picker("Language", selection: $transcriptionLanguage) {
                                Text("Auto-detect").tag("auto")
                                Divider()
                                ForEach(TranscriptionLanguage.all, id: \.code) { language in
                                    Text(language.name).tag(language.code)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                        .accessibilityLabel("Language: \(currentLanguageLabel)")
                    }
                }

                SettingsGroup("General") {
                    SettingRow("Launch at login", description: "Start Shh.. in the menu bar when you log in.", isFirst: true) {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .toggleStyle(.graphiteSwitch)
                            .labelsHidden()
                    }
                    SettingRow(
                        "Clear history",
                        description: isConfirmingClear
                            ? "Delete all \(dictations)? This can't be undone."
                            : count > 0 ? "\(dictations) stored on this Mac." : "No dictations stored.",
                        isWarning: isConfirmingClear
                    ) {
                        if isConfirmingClear {
                            Button("Cancel") { isConfirmingClear = false }
                                .buttonStyle(.graphite(.plain))
                                .keyboardShortcut(.cancelAction)
                            Button("Delete all", action: clearHistory)
                                .buttonStyle(.graphite(.primary))
                        } else {
                            Button("Clear…") { isConfirmingClear = true }
                                .buttonStyle(.graphite(.ghost))
                                .disabled(count == 0)
                        }
                    }
                }
            }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert the switch on failure
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Actions

    private func clearHistory() {
        for entry in entries {
            modelContext.delete(entry)
        }
        try? modelContext.save()
        isConfirmingClear = false
    }
}

// MARK: - Transcription Languages

private struct TranscriptionLanguage {
    let name: String
    let code: String

    static let all: [TranscriptionLanguage] = [
        .init(name: "English", code: "en"),
        .init(name: "Spanish", code: "es"),
        .init(name: "French", code: "fr"),
        .init(name: "German", code: "de"),
        .init(name: "Italian", code: "it"),
        .init(name: "Portuguese", code: "pt"),
        .init(name: "Chinese", code: "zh"),
        .init(name: "Japanese", code: "ja"),
        .init(name: "Korean", code: "ko"),
        .init(name: "Russian", code: "ru"),
        .init(name: "Arabic", code: "ar"),
        .init(name: "Dutch", code: "nl"),
        .init(name: "Polish", code: "pl"),
        .init(name: "Turkish", code: "tr"),
        .init(name: "Hindi", code: "hi"),
    ]
}
