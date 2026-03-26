import SwiftUI
import SwiftData

struct LLMProvidersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LLMProviderConfig.modelName) private var providers: [LLMProviderConfig]
    @State private var showCreateSheet = false
    @State private var editingProvider: LLMProviderConfig?
    @State private var isAddHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if providers.isEmpty {
                emptyState
            } else {
                providerList
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showCreateSheet) {
            ProviderFormSheet(mode: .create)
        }
        .sheet(item: $editingProvider) { provider in
            ProviderFormSheet(mode: .edit(provider))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("LLM Providers")
                .font(Font.appTitle3)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
            Spacer()
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(Font.appTitle3)
                    .foregroundStyle(isAddHovered ? Color.appError : Color.appForeground.opacity(0.8))
            }
            .buttonStyle(.plain)
            .onHover { isAddHovered = $0 }
            .help("New Provider")
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Providers", systemImage: "brain")
        } description: {
            Text("Add an LLM provider to enable AI-powered text processing.")
        } actions: {
            Button("Add Provider") {
                showCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - List

    private var providerList: some View {
        List {
            ForEach(providers) { provider in
                ProviderRow(
                    provider: provider,
                    onToggleActive: { toggleActive(provider) },
                    onEdit: { editingProvider = provider },
                    onDelete: { deleteProvider(provider) }
                )
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    // MARK: - Actions

    private func toggleActive(_ provider: LLMProviderConfig) {
        if provider.isActive {
            provider.isActive = false
        } else {
            try? provider.activate(in: modelContext)
        }
    }

    private func deleteProvider(_ provider: LLMProviderConfig) {
        modelContext.delete(provider)
    }
}

// MARK: - Provider Row

private struct ProviderRow: View {
    let provider: LLMProviderConfig
    let onToggleActive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var isRowHovered = false

    private var providerLabel: String {
        switch provider.providerType {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .local: "Local"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(providerLabel)
                        .font(Font.appBody)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appForeground)
                    if provider.isActive {
                        Text("Active")
                            .font(Font.appCaption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.appError)
                            .clipShape(Capsule())
                    }
                }
                if !provider.modelName.isEmpty {
                    Text(provider.modelName)
                        .font(Font.appCaption)
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                        .lineLimit(2)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { provider.isActive },
                set: { _ in onToggleActive() }
            ))
            .toggleStyle(.switch)
            .tint(Color.appError)
            .labelsHidden()
        }
        .padding(20)
        .background(
            isRowHovered
                ? Color.appForeground.opacity(0.08)
                : Color.appForeground.opacity(0.05)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
             RoundedRectangle(cornerRadius: 8)
                 .stroke(
                    Color.appForeground.opacity(0.1),
                    lineWidth: 1
                 )
        )
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
        .onTapGesture { onEdit() }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete Provider", isPresented: $showDeleteConfirmation) {
            Button("Delete \"\(providerLabel)\"", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete this provider? This action cannot be undone.")
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
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @FocusState private var focusedField: ProviderField?
    private enum ProviderField: Hashable { case apiKey, endpointURL, modelName }

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
            // Sheet header
            HStack {
                Text(isEditing ? "Edit Provider" : "New Provider")
                    .font(Font.appTitle3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appForeground)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Font.appBody)
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            Divider()

            // Form body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Provider type
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provider Type")
                            .font(Font.appSubheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appForeground.opacity(0.7))
                        Picker("", selection: $providerType) {
                            Text("Anthropic").tag(LLMProviderType.anthropic)
                            Text("OpenAI").tag(LLMProviderType.openAI)
                            Text("Local").tag(LLMProviderType.local)
                        }
                        .pickerStyle(.menu)
                        .tint(Color.appError)
                    }

                    // API Key (cloud only)
                    if isCloud {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(Font.appSubheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appForeground.opacity(0.7))
                            SecureField("", text: $apiKey)
                                .focused($focusedField, equals: .apiKey)
                                .font(Font.appBody)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Color.appForeground)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.appForeground.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.appForeground.opacity(0.12), lineWidth: 1)
                                )
                        }
                    }

                    // Endpoint URL
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isCloud ? "Endpoint URL (optional)" : "Endpoint URL")
                            .font(Font.appSubheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appForeground.opacity(0.7))
                        TextField("", text: $endpointURL)
                            .focused($focusedField, equals: .endpointURL)
                            .font(Font.appBody)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Color.appForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.appForeground.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appForeground.opacity(0.12), lineWidth: 1)
                            )
                    }

                    // Model name
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Model Name")
                                .font(Font.appSubheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appForeground.opacity(0.7))
                            Spacer()
                            if providerType != .anthropic {
                                Button {
                                    Task { await fetchModels() }
                                } label: {
                                    HStack(spacing: 4) {
                                        if isLoadingModels {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(Font.appCaption)
                                        }
                                        Text("Fetch Models")
                                            .font(Font.appCaption)
                                    }
                                    .foregroundStyle(Color.appError)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoadingModels)
                            }
                        }
                        if !availableModels.isEmpty {
                            Picker("", selection: $modelName) {
                                if !modelName.isEmpty && !availableModels.contains(modelName) {
                                    Text(modelName).tag(modelName)
                                }
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.appError)
                        } else {
                            TextField("", text: $modelName)
                                .focused($focusedField, equals: .modelName)
                                .font(Font.appBody)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Color.appForeground)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.appForeground.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.appForeground.opacity(0.12), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .font(Font.appBody)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.appForeground.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)

                Spacer()

                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .font(Font.appBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(isValid ? .white : Color.appForeground.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isValid ? Color.appError : Color.appForeground.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 460)
        .background(Color.appBackground)
        .onAppear {
            if case .edit(let config) = mode {
                providerType = config.providerType
                apiKey = config.apiKey
                endpointURL = config.endpointURL
                modelName = config.modelName
            }
            if providerType == .anthropic {
                availableModels = Self.anthropicModels
                if modelName.isEmpty, let first = availableModels.first {
                    modelName = first
                }
            }
        }
        .onChange(of: providerType) { _, newType in
            if newType == .anthropic {
                availableModels = Self.anthropicModels
                modelName = availableModels.first ?? ""
            } else {
                availableModels = []
                modelName = ""
            }
        }
    }

    private static let anthropicModels = [
        "claude-sonnet-4-20250514",
        "claude-3-5-haiku-20241022",
        "claude-3-opus-20240229"
    ]

    private func fetchModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }

        let baseURL: String
        switch providerType {
        case .openAI:
            baseURL = endpointURL.isEmpty ? "https://api.openai.com" : endpointURL
        case .local:
            baseURL = endpointURL.isEmpty ? "http://localhost:1234" : endpointURL
        case .anthropic:
            return
        }

        let urlString = baseURL.hasSuffix("/") ? "\(baseURL)v1/models" : "\(baseURL)/v1/models"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
            availableModels = response.data.map(\.id).sorted()
            if !availableModels.isEmpty && !availableModels.contains(modelName) {
                modelName = availableModels[0]
            }
        } catch {
            availableModels = []
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
