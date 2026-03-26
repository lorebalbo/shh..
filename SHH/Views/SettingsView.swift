import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DictationEntry]
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "auto"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showClearHistoryConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    transcriptionSection
                    generalSection
                }
                .padding(24)
            }
        }
        .background(Color.appBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(Font.appTitle3)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transcription", systemImage: "waveform")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)

                Picker(selection: $transcriptionLanguage) {
                    Text("Auto-detect").tag("auto")
                    Divider()
                    ForEach(TranscriptionLanguage.all, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                } label: {
                    Text("Language")
                        .font(Font.appBody)
                        .foregroundStyle(Color.appForeground)
                }
                .tint(Color.appError)
            .frame(maxWidth: 300)
        }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("General", systemImage: "gearshape")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .font(Font.appBody)
                    .foregroundStyle(Color.appForeground)
                    .toggleStyle(.switch)
                    .tint(Color.appError)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear History")
                            .font(Font.appBody)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.appForeground)
                        Text("\(entries.count) dictation\(entries.count == 1 ? "" : "s") stored")
                            .font(Font.appCaption)
                            .foregroundStyle(Color.appForeground.opacity(0.5))
                    }
                    Spacer()
                    Button(action: { showClearHistoryConfirmation = true }) {
                        Text("Clear All")
                            .font(Font.appBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(entries.isEmpty ? Color.appForeground.opacity(0.12) : Color.appError)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(entries.isEmpty)
                }
            }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
        .confirmationDialog("Clear History", isPresented: $showClearHistoryConfirmation) {
            Button("Delete All Dictations", role: .destructive) {
                clearHistory()
            }
        } message: {
            Text("Are you sure you want to delete all \(entries.count) dictation\(entries.count == 1 ? "" : "s")? This action cannot be undone.")
        }
    }

    // MARK: - Actions

    private func clearHistory() {
        for entry in entries {
            modelContext.delete(entry)
        }
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
