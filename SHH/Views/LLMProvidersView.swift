import SwiftData
import SwiftUI

/// One row per provider type. Each row edits that type's config in place; the switch
/// makes it the active provider (one at a time).
struct LLMProvidersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [LLMProviderConfig]
    @State private var expanded: LLMProviderType?
    @State private var models: [LLMProviderType: [String]] = [:]
    @State private var fetchStatus: [LLMProviderType: FetchStatus] = [:]
    @FocusState private var focusedField: ConnectionField?

    private static let types: [LLMProviderType] = [.openAI, .local]

    private enum FetchStatus: Equatable {
        case loading
        case done(String)
    }

    private enum ConnectionField: Hashable {
        case apiKey(LLMProviderType)
        case endpoint(LLMProviderType)
    }

    var body: some View {
        PageScaffold(.providers) {
            HairlineStack(Self.types.compactMap(config(for:)), isHoverable: { _ in false }) { config in
                providerRow(config)
            }
        }
        .onAppear(perform: ensureConfigs)
        .task { await fetchModelsForConfiguredProviders() }
    }

    /// The config a row edits: the active one of that type if there is one, otherwise the first.
    private func config(for type: LLMProviderType) -> LLMProviderConfig? {
        let ofType = configs.filter { $0.providerType == type }
        return ofType.first(where: \.isActive) ?? ofType.first
    }

    // MARK: - Row

    private func providerRow(_ config: LLMProviderConfig) -> some View {
        let type = config.providerType
        let isOpen = expanded == type
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    toggleExpanded(type)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Graphite.text3)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(type.displayName)
                                .font(.inter(14.5, .medium))
                                .foregroundStyle(Graphite.text)
                            meta(config)
                                .font(.inter(12.5))
                                .foregroundStyle(Graphite.text3)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, -6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(type.displayName) connection settings")
                .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

                modelMenu(config)

                Toggle("Use \(type.displayName)", isOn: Binding(
                    get: { config.isActive },
                    set: { setActive(config, $0) }
                ))
                .toggleStyle(.graphiteSwitch)
                .labelsHidden()
            }

            if isOpen {
                connection(config)
                    .padding(.top, 20)
                    .padding(.bottom, 6)
                    .padding(.leading, 28)
            }
        }
        .listRowPadding()
        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.15), value: isOpen)
    }

    private func meta(_ config: LLMProviderConfig) -> Text {
        if config.providerType.isCloud {
            let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return Text(key.isEmpty ? "Cloud · needs an API key" : "Cloud · key ••••\(key.suffix(4))")
        }
        let endpoint = config.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return Text("Local · needs an endpoint") }
        return Text("Local · \(host(endpoint))")
    }

    private func modelMenu(_ config: LLMProviderConfig) -> some View {
        let type = config.providerType
        var choices = models[type] ?? []
        if !config.modelName.isEmpty && !choices.contains(config.modelName) {
            choices.insert(config.modelName, at: 0)
        }
        return GraphiteMenu(config.modelName.isEmpty ? "Choose a model" : config.modelName, width: 184) {
            if choices.isEmpty {
                Button(fetchStatus[type] == .loading ? "Fetching models…" : "No models yet") {}
                    .disabled(true)
            } else {
                Picker("Model", selection: Binding(
                    get: { config.modelName },
                    set: { name in
                        config.modelName = name
                        try? modelContext.save()
                    }
                )) {
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Divider()
            Button {
                Task { await fetchModels(config) }
            } label: {
                Label("Refresh models", systemImage: "arrow.clockwise")
            }
        }
        .accessibilityLabel("\(type.displayName) model: \(config.modelName.isEmpty ? "none" : config.modelName)")
    }

    // MARK: - Connection

    private func connection(_ config: LLMProviderConfig) -> some View {
        let type = config.providerType
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                if type.isCloud {
                    FieldBlock("API key") {
                        GraphiteTextField(
                            placeholder: "sk-…",
                            text: binding(config, \.apiKey),
                            isSecure: true,
                            focus: $focusedField,
                            field: .apiKey(type)
                        )
                        .onSubmit { Task { await fetchModels(config) } }
                    }
                    .frame(maxWidth: .infinity)
                }
                FieldBlock("Endpoint URL", isOptional: type.isCloud) {
                    GraphiteTextField(
                        placeholder: type.isCloud ? "https://api.openai.com/v1" : "http://localhost:1234/v1",
                        text: binding(config, \.endpointURL),
                        focus: $focusedField,
                        field: .endpoint(type)
                    )
                    .onSubmit { Task { await fetchModels(config) } }
                }
                .frame(maxWidth: type.isCloud ? .infinity : 360)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await fetchModels(config) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        Text("Fetch models")
                    }
                }
                .buttonStyle(.graphite(.ghost))
                .disabled(fetchStatus[type] == .loading)

                Group {
                    switch fetchStatus[type] {
                    case .loading:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Fetching models…")
                        }
                    case .done(let message):
                        Text(message)
                    case nil:
                        EmptyView()
                    }
                }
                .font(.inter(12.5))
                .foregroundStyle(Graphite.text3)
                .lineLimit(1)

                Spacer(minLength: 0)

                Button("Done") { toggleExpanded(type) }
                    .buttonStyle(.graphite(.plain))
                    .keyboardShortcut(.cancelAction)
                    .padding(.trailing, -10)
            }
        }
    }

    /// Writes straight into the stored config, and clears the last fetch result.
    private func binding(_ config: LLMProviderConfig, _ keyPath: ReferenceWritableKeyPath<LLMProviderConfig, String>) -> Binding<String> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { value in
                config[keyPath: keyPath] = value
                fetchStatus[config.providerType] = nil
                try? modelContext.save()
            }
        )
    }

    // MARK: - Actions

    private func ensureConfigs() {
        let existing = (try? modelContext.fetch(FetchDescriptor<LLMProviderConfig>())) ?? []
        var inserted = false
        for type in Self.types where !existing.contains(where: { $0.providerType == type }) {
            modelContext.insert(LLMProviderConfig(
                providerType: type,
                endpointURL: type == .local ? "http://localhost:1234/v1" : ""
            ))
            inserted = true
        }
        if inserted { try? modelContext.save() }
    }

    private func toggleExpanded(_ type: LLMProviderType) {
        if expanded == type {
            expanded = nil
            focusedField = nil
        } else {
            expanded = type
            DispatchQueue.main.async { focusedField = type.isCloud ? .apiKey(type) : .endpoint(type) }
        }
    }

    private func isConfigured(_ config: LLMProviderConfig) -> Bool {
        let detail = config.providerType.isCloud ? config.apiKey : config.endpointURL
        return !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func setActive(_ config: LLMProviderConfig, _ isOn: Bool) {
        let type = config.providerType
        guard isOn else {
            config.isActive = false
            try? modelContext.save()
            return
        }
        // Turning on a provider without connection details opens them instead.
        guard isConfigured(config) else {
            expanded = type
            DispatchQueue.main.async { focusedField = type.isCloud ? .apiKey(type) : .endpoint(type) }
            return
        }
        try? config.activate(in: modelContext)
        try? modelContext.save()
        if config.modelName.isEmpty {
            Task { await fetchModels(config) }
        }
    }

    private func fetchModelsForConfiguredProviders() async {
        for type in Self.types {
            guard models[type] == nil, let config = config(for: type), isConfigured(config) else { continue }
            await fetchModels(config, quietly: true)
        }
    }

    /// Lists the provider's models from its OpenAI-compatible `/v1/models` endpoint.
    /// A quiet fetch doesn't report its result under the connection fields.
    private func fetchModels(_ config: LLMProviderConfig, quietly: Bool = false) async {
        let type = config.providerType
        if !quietly { fetchStatus[type] = .loading }

        let endpoint = config.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = endpoint.isEmpty ? type.defaultBaseURL : endpoint
        // Strip trailing slashes and any /v1 suffix so we don't end up with /v1/v1/models.
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        if base.hasSuffix("/v1") { base = String(base.dropLast(3)) }
        guard let url = URL(string: "\(base)/v1/models") else {
            if !quietly { fetchStatus[type] = .done("That endpoint isn't a valid URL") }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                if !quietly { fetchStatus[type] = .done("The API key was rejected") }
                return
            }
            let names = try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id).sorted()
            models[type] = names
            // A background fetch only fills in a missing model; it never replaces the user's pick.
            if let first = names.first,
               config.modelName.isEmpty || (!quietly && !names.contains(config.modelName)) {
                config.modelName = first
                try? modelContext.save()
            }
            if !quietly {
                fetchStatus[type] = .done(names.count == 1 ? "1 model available" : "\(names.count) models available")
            }
        } catch {
            if !quietly { fetchStatus[type] = .done("Couldn't reach \(host(base))") }
        }
    }

    private func host(_ url: String) -> String {
        var host = url
        for scheme in ["https://", "http://"] where host.hasPrefix(scheme) {
            host = String(host.dropFirst(scheme.count))
        }
        while host.hasSuffix("/") { host = String(host.dropLast()) }
        return host
    }
}

extension LLMProviderType {
    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .local: "Local"
        default: rawValue.capitalized
        }
    }

    var isCloud: Bool { self != .local }

    fileprivate var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com"
        case .local: "http://localhost:1234/v1"
        default: ""
        }
    }
}
