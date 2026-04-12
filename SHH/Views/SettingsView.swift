import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DictationEntry]
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "auto"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showClearHistoryConfirmation = false
    @State private var pendingDownloadModel: KnownWhisperModel? = nil
    @State private var modelManager = ModelManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    transcriptionSection
                    whisperModelsSection
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
                .font(Font.appHeadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
                .alignmentGuide(VerticalAlignment.center) { d in
                    d[.firstTextBaseline] / 2
                }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    // MARK: - Transcription Section

    private var currentLanguageLabel: String {
        if transcriptionLanguage == "auto" { return "Auto-detect" }
        return TranscriptionLanguage.all.first { $0.code == transcriptionLanguage }?.name ?? transcriptionLanguage
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcription", systemImage: "waveform")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)

            VStack(alignment: .leading, spacing: 6) {
                Text("Language")
                    .font(Font.appSubheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                Menu {
                    Button("Auto-detect") { transcriptionLanguage = "auto" }
                    Divider()
                    ForEach(TranscriptionLanguage.all, id: \.code) { lang in
                        Button(lang.name) { transcriptionLanguage = lang.code }
                    }
                } label: {
                    HStack {
                        Text(currentLanguageLabel)
                            .font(Font.appBody)
                            .foregroundStyle(Color.appForeground)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(Font.appCaption)
                            .foregroundStyle(Color.appForeground.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.appForeground.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .environment(\.colorScheme, .light)
                .frame(maxWidth: 300)
            }
        }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Whisper Models Section

    private var whisperModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcription Model", systemImage: "cpu")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)

            VStack(spacing: 0) {
                ForEach(Array(KnownWhisperModel.catalog.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        Divider()
                            .background(Color.appForeground.opacity(0.08))
                    }
                    modelRow(model)
                }
            }
            .background(Color.appForeground.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
        }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
        .confirmationDialog(
            "Download \(pendingDownloadModel?.displayName ?? "") Model",
            isPresented: Binding(
                get: { pendingDownloadModel != nil },
                set: { if !$0 { pendingDownloadModel = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let model = pendingDownloadModel {
                Button("Download (\(model.displaySize))") {
                    modelManager.downloadModel(model)
                    pendingDownloadModel = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDownloadModel = nil }
        } message: {
            if let model = pendingDownloadModel {
                Text(
                    "This will download the \(model.displayName) Whisper model (\(model.displaySize)) from Hugging Face. " +
                    "Download time depends on your connection speed."
                )
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: KnownWhisperModel) -> some View {
        let state = modelManager.downloadStates[model.id] ?? .notDownloaded
        let isActive = modelManager.activeModelId == model.id
        let isDownloaded = state == .downloaded

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(Font.appBody)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(isDownloaded ? Color.appForeground : Color.appForeground.opacity(0.45))
                    if model.isMostPowerful {
                        Text("BEST")
                            .font(Font.appCaption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appError)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.appError.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(model.description)
                    .font(Font.appCaption)
                    .foregroundStyle(
                        isDownloaded
                            ? Color.appForeground.opacity(0.5)
                            : Color.appForeground.opacity(0.3)
                    )
            }

            Spacer()

            Text(model.displaySize)
                .font(Font.appCaption)
                .foregroundStyle(
                    isDownloaded
                        ? Color.appForeground.opacity(0.5)
                        : Color.appForeground.opacity(0.3)
                )
                .monospacedDigit()

            modelRowAction(model: model, state: state, isActive: isActive)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(isDownloaded ? 1.0 : 0.75)
    }

    @ViewBuilder
    private func modelRowAction(model: KnownWhisperModel, state: ModelDownloadState, isActive: Bool) -> some View {
        switch state {
        case .downloaded:
            let isOn = Binding<Bool>(
                get: { modelManager.activeModelId == model.id },
                set: { newValue in
                    if newValue { modelManager.setActiveModel(model) }
                    // Turning off the active model is not allowed — only switching activates another
                }
            )
            Toggle("", isOn: isOn)
                .toggleStyle(AppToggleStyle())
                .labelsHidden()

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.appError)
                    .frame(width: 56)
                Button {
                    modelManager.cancelDownload(model)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appForeground.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            }

        case .notDownloaded, .failed(_):
            Button {
                pendingDownloadModel = model
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appForeground.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Download \(model.displayName) (\(model.displaySize))")
        }
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
                    .toggleStyle(AppToggleStyle())
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
