import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LLMProviderConfig.modelName) private var providers: [LLMProviderConfig]
    @Query private var entries: [DictationEntry]
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "auto"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showProviderSheet = false
    @State private var editingProvider: LLMProviderConfig?
    @State private var showClearHistoryConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    llmProvidersSection
                    transcriptionSection
                    generalSection
                }
                .padding(24)
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showProviderSheet) {
            ProviderFormSheet(mode: .create)
        }
        .sheet(item: $editingProvider) { provider in
            ProviderFormSheet(mode: .edit(provider))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(Font.appLargeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - LLM Providers Section

    private var llmProvidersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LLM Providers", systemImage: "brain")
                    .font(Font.appHeadline)
                    .foregroundStyle(Color.appForeground)
                    Spacer()
                    Button {
                        showProviderSheet = true
                    } label: {
                        Label("Add Provider", systemImage: "plus")
                    }
                    .controlSize(.small)
                }

                if providers.isEmpty {
                    Text("No providers configured. Add one to enable AI text processing.")
                        .foregroundStyle(.secondary)
                        .font(Font.appCallout)
                        .padding(.vertical, 8)
                } else {
                    ForEach(providers) { provider in
                        ProviderRow(
                            provider: provider,
                            onToggleActive: { toggleProviderActive(provider) },
                            onEdit: { editingProvider = provider },
                            onDelete: { deleteProvider(provider) }
                        )
                        if provider.id != providers.last?.id {
                            Divider()
                        }
                    }
            }
        }
        .padding(16)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appForeground.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transcription", systemImage: "waveform")
                .font(Font.appHeadline)
                .foregroundStyle(Color.appForeground)

                Picker("Language", selection: $transcriptionLanguage) {
                    Text("Auto-detect").tag("auto")
                    Divider()
                    ForEach(TranscriptionLanguage.all, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
            }
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
                            .fontWeight(.medium)
                        Text("\(entries.count) dictation\(entries.count == 1 ? "" : "s") stored")
                            .font(Font.appCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        showClearHistoryConfirmation = true
                    }
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

    private func toggleProviderActive(_ provider: LLMProviderConfig) {
        if provider.isActive {
            provider.isActive = false
        } else {
            try? provider.activate(in: modelContext)
        }
    }

    private func deleteProvider(_ provider: LLMProviderConfig) {
        modelContext.delete(provider)
    }

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

// MARK: - Provider Row

private struct ProviderRow: View {
    let provider: LLMProviderConfig
    let onToggleActive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleActive) {
                Image(systemName: provider.isActive ? "checkmark.circle.fill" : "circle")
                    .font(Font.appTitle3)
                    .foregroundStyle(provider.isActive ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(provider.isActive ? "Deactivate provider" : "Activate provider")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(providerLabel)
                        .fontWeight(.medium)
                    if provider.isActive {
                        Text("Active")
                            .font(Font.appCaption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                if !provider.modelName.isEmpty {
                    Text("Model: \(provider.modelName)")
                        .font(Font.appCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit provider")

            Button(action: { showDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete provider")
        }
        .confirmationDialog("Delete Provider", isPresented: $showDeleteConfirmation) {
            Button("Delete Provider", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete this provider? This action cannot be undone.")
        }
    }

    private var providerLabel: String {
        switch provider.providerType {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .local: "Local"
        }
    }
}

// MARK: - Provider Form Sheet

private struct ProviderFormSheet: View {
    enum Mode: Identifiable {
        case create
        case edit(LLMProviderConfig)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let config): config.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var providerType: LLMProviderType = .anthropic
    @State private var apiKey: String = ""
    @State private var endpointURL: String = ""
    @State private var modelName: String = ""

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isCloud: Bool {
        providerType != .local
    }

    private var isValid: Bool {
        if isCloud {
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return !endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? "Edit Provider" : "Add Provider")
                .font(Font.appHeadline)
                .padding(.top, 16)

            Form {
                Picker("Provider Type", selection: $providerType) {
                    Text("Anthropic").tag(LLMProviderType.anthropic)
                    Text("OpenAI").tag(LLMProviderType.openAI)
                    Text("Local").tag(LLMProviderType.local)
                }

                if isCloud {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Endpoint URL (optional)", text: $endpointURL)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Endpoint URL", text: $endpointURL)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Model Name", text: $modelName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 420)
        .onAppear {
            if case .edit(let config) = mode {
                providerType = config.providerType
                apiKey = config.apiKey
                endpointURL = config.endpointURL
                modelName = config.modelName
            }
        }
    }

    private func save() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let config = LLMProviderConfig(
                providerType: providerType,
                apiKey: trimmedKey,
                endpointURL: trimmedURL,
                modelName: trimmedModel
            )
            modelContext.insert(config)
        case .edit(let config):
            config.providerType = providerType
            config.apiKey = trimmedKey
            config.endpointURL = trimmedURL
            config.modelName = trimmedModel
        }
        dismiss()
    }
}
