import SwiftUI

/// A speech-to-text engine and its models. Whisper is the only engine so far;
/// the page groups models by engine so others (e.g. Parakeet) can join it.
struct SpeechEngine: Identifiable {
    let id: String
    let name: String
    let meta: String
    let models: [KnownWhisperModel]

    static let all: [SpeechEngine] = [
        SpeechEngine(
            id: "whisper",
            name: "Whisper",
            meta: "OpenAI · 99 languages",
            models: KnownWhisperModel.catalog.sorted { $0.approximateBytes < $1.approximateBytes }
        ),
    ]
}

extension KnownWhisperModel {
    /// "Whisper Small"
    var fullName: String { "Whisper \(displayName)" }

    /// The base model ships inside the app and can't be deleted.
    var isBundled: Bool { id == "base" }

    static var fallback: KnownWhisperModel? { catalog.first(where: \.isBundled) }
}

struct SpeechModelsView: View {
    @Environment(DashboardModel.self) private var dashboard
    @AppStorage("transcriptionEnabled") private var transcriptionEnabled = true
    @State private var modelManager = ModelManager.shared
    /// A picked model that isn't on disk yet; the row offers to download it.
    @State private var chosenId: String?
    @State private var openEngines: Set<String> = ["whisper"]
    @State private var confirmingDelete: String?
    @State private var listWidth: CGFloat = 680

    private var selectedId: String {
        chosenId ?? modelManager.pendingActivationId ?? modelManager.activeModelId
    }

    private var activeModel: KnownWhisperModel? {
        KnownWhisperModel.catalog.first { $0.id == modelManager.activeModelId }
    }

    var body: some View {
        PageScaffold(.speech) {
            Text("On-device transcription")
                .font(.sans(13.5, .medium))
                .foregroundStyle(Ink.text)
                .onTapGesture { transcriptionEnabled.toggle() }
                .accessibilityHidden(true)
            Toggle("On-device transcription", isOn: $transcriptionEnabled)
                .toggleStyle(.inkSwitch)
                .labelsHidden()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if !transcriptionEnabled {
                    HStack(spacing: 10) {
                        Circle().strokeBorder(Ink.ink, lineWidth: 2).frame(width: 9, height: 9)
                        Text("Transcription is off. Holding fn won't record until you turn it back on.")
                            .font(.sans(14, .medium))
                            .foregroundStyle(Ink.text)
                    }
                    .padding(.bottom, 24)
                }
                VStack(spacing: 0) {
                    ForEach(Array(SpeechEngine.all.enumerated()), id: \.element.id) { index, engine in
                        engineSection(engine)
                            .padding(.vertical, 6)
                            .overlay(alignment: .top) {
                                if index > 0 {
                                    Rectangle().fill(Ink.hairline).frame(height: 1).padding(.horizontal, 14)
                                }
                            }
                            .padding(.top, index == 0 ? 0 : 10)
                    }
                }
                .padding(.horizontal, -14)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
                .opacity(transcriptionEnabled ? 1 : 0.4)
                .allowsHitTesting(transcriptionEnabled)
                .animation(.easeOut(duration: 0.2), value: transcriptionEnabled)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Speech model")
            }
        }
    }

    // MARK: - Engine

    private func engineSection(_ engine: SpeechEngine) -> some View {
        let isOpen = openEngines.contains(engine.id)
        let onDisk = engine.models
            .filter { modelManager.downloadStates[$0.id] == .downloaded }
            .reduce(Int64(0)) { $0 + $1.approximateBytes }
        let inUse = engine.models.first { $0.id == modelManager.activeModelId }

        return VStack(spacing: 0) {
            Button {
                if isOpen { openEngines.remove(engine.id) } else { openEngines.insert(engine.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Ink.text3)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 18)
                    SectionTitle(engine.name)
                        .fixedSize()
                    Text(engine.meta)
                        .font(.sans(12.5))
                        .foregroundStyle(Ink.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(engine.meta)
                    Spacer(minLength: 12)
                    HStack(spacing: 12) {
                        if let inUse, !isOpen {
                            DotLabel("\(inUse.displayName) in use")
                        }
                        if onDisk > 0 {
                            Text("\(Ink.formatBytes(onDisk)) on disk").monospacedDigit()
                        } else {
                            Text("Not downloaded")
                        }
                    }
                    .font(.sans(12.5))
                    .foregroundStyle(Ink.text3)
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hoverFill(cornerRadius: 21)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOpen)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                ForEach(engine.models) { model in
                    modelRow(model)
                }
            }
        }
    }

    // MARK: - Model row

    private func modelRow(_ model: KnownWhisperModel) -> some View {
        let state = modelManager.downloadStates[model.id] ?? .notDownloaded
        let progress: Double? = if case .downloading(let progress) = state { progress } else { nil }
        let isReady = state == .downloaded
        let isSelected = selectedId == model.id
        let isOffering = isSelected && !isReady && progress == nil && modelManager.activeModelId != model.id
        let size = Ink.formatBytes(model.approximateBytes)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { pick(model) } label: { RadioMark(isOn: isSelected) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(model.fullName), \(size), \(statusDescription(model, state))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                Text(model.displayName)
                    .font(.sans(14, .semibold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .frame(width: 76, alignment: .leading)
                Group {
                    if listWidth > 470 {
                        modelDescription(model, state: state, progress: progress)
                            .font(.sans(14))
                            .foregroundStyle(Ink.text2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(size)
                    .font(.sans(12.5))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text2)
                    .frame(width: 62, alignment: .trailing)
                modelStatus(model, state: state, progress: progress, isOffering: isOffering)
                    .font(.sans(12.5))
                    .frame(width: 96, alignment: .trailing)
                modelAction(model, state: state, isDownloading: progress != nil)
                    .frame(width: 30)
            }
            .frame(minHeight: 42)

            Group {
                if confirmingDelete == model.id {
                    deleteConfirm(model)
                } else if isOffering {
                    downloadOffer(model)
                }
            }
            .padding(.leading, 30)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) {
            if let progress {
                ProgressTrack(progress: progress)
                    .padding(.leading, 44)
                    .padding(.trailing, 14)
                    .padding(.bottom, 2)
                    .accessibilityLabel("\(model.fullName) download")
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            }
        }
        .contentShape(Rectangle())
        .hoverFill(cornerRadius: 21)
        .onTapGesture { pick(model) }
        .contextMenu {
            if progress == nil { modelMenuItems(model, state: state) }
        }
    }

    @ViewBuilder
    private func modelDescription(_ model: KnownWhisperModel, state: ModelDownloadState, progress: Double?) -> some View {
        if let progress {
            Text("Downloading · ")
                + Text(Ink.formatBytes(Int64(Double(model.approximateBytes) * progress))).monospacedDigit()
        } else if case .failed(let message) = state {
            Text("Download failed").fontWeight(.semibold).foregroundStyle(Ink.text).help(message)
        } else {
            Text(model.description).help(model.description)
        }
    }

    @ViewBuilder
    private func modelStatus(_ model: KnownWhisperModel, state: ModelDownloadState, progress: Double?, isOffering: Bool) -> some View {
        if let progress {
            Text("\(Int((progress * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(Ink.text3)
        } else if modelManager.activeModelId == model.id {
            DotLabel("In use")
        } else if state == .downloaded {
            Text(model.isBundled ? "Built in" : "On disk").foregroundStyle(Ink.text3)
        } else if !isOffering {
            // The offer below the row already has its own Download button.
            Button {
                download(model, andUse: false)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 10.5, weight: .semibold))
                    Text("Download")
                }
            }
            .buttonStyle(InkChipButtonStyle())
            .padding(.trailing, -6)
            .disabled(modelManager.isDownloading)
            .help(modelManager.isDownloading ? "One download at a time" : "Download \(Ink.formatBytes(model.approximateBytes))")
            .accessibilityLabel("Download \(model.fullName), \(Ink.formatBytes(model.approximateBytes))")
        }
    }

    @ViewBuilder
    private func modelAction(_ model: KnownWhisperModel, state: ModelDownloadState, isDownloading: Bool) -> some View {
        let isInUse = modelManager.activeModelId == model.id
        if isDownloading {
            Button {
                cancelDownload(model)
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(InkIconButtonStyle())
            .help("Cancel download")
            .accessibilityLabel("Cancel download")
        } else if state != .downloaded || !isInUse || !model.isBundled {
            RowMenuButton(model.fullName) { modelMenuItems(model, state: state) }
        } else {
            Color.clear.frame(width: 30, height: 30)
        }
    }

    @ViewBuilder
    private func modelMenuItems(_ model: KnownWhisperModel, state: ModelDownloadState) -> some View {
        let isInUse = modelManager.activeModelId == model.id
        if state != .downloaded {
            Button { download(model, andUse: true) } label: {
                Label("Download and use", systemImage: "arrow.down.to.line")
            }
            .disabled(modelManager.isDownloading)
            Button { download(model, andUse: false) } label: {
                Label("Download only · \(Ink.formatBytes(model.approximateBytes))", systemImage: "arrow.down.to.line")
            }
            .disabled(modelManager.isDownloading)
        } else {
            if !isInUse {
                Button { pick(model) } label: { Label("Use", systemImage: "smallcircle.filled.circle") }
            }
            if !model.isBundled {
                if !isInUse { Divider() }
                Button(role: .destructive) { askToDelete(model) } label: {
                    Label("Delete from this Mac…", systemImage: "trash")
                }
            }
        }
    }

    private func deleteConfirm(_ model: KnownWhisperModel) -> some View {
        let name = Text(model.displayName).font(.sans(14, .semibold)).foregroundColor(Ink.text)
        let frees = "Frees \(Ink.formatBytes(model.approximateBytes))."
        let message = modelManager.activeModelId == model.id
            ? name + Text(" is in use. Delete it and switch to \(KnownWhisperModel.fallback?.fullName ?? "Whisper Base")? \(frees)")
            : Text("Delete ") + name + Text(" from this Mac? \(frees)")
        return InlineConfirm(
            message: message,
            confirmTitle: "Delete",
            onCancel: { confirmingDelete = nil },
            onConfirm: { delete(model) }
        )
    }

    private func downloadOffer(_ model: KnownWhisperModel) -> some View {
        let name = Text(model.displayName).font(.sans(14, .semibold)).foregroundColor(Ink.text)
        return HStack(spacing: 8) {
            (Text("\(activeModel?.fullName ?? "The current model") stays in use until ") + name + Text(" is downloaded."))
                .font(.sans(14))
                .foregroundStyle(Ink.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Not now") { chosenId = nil }
                .buttonStyle(.ink(.plain))
                .keyboardShortcut(.cancelAction)
            Button("Download \(Ink.formatBytes(model.approximateBytes))") { download(model, andUse: true) }
                .buttonStyle(.ink(.primary))
                .disabled(modelManager.isDownloading)
                .help(modelManager.isDownloading ? "One download at a time" : "")
        }
    }

    private func statusDescription(_ model: KnownWhisperModel, _ state: ModelDownloadState) -> String {
        switch state {
        case .downloading: return "downloading"
        case .failed: return "download failed"
        case .notDownloaded: return "not downloaded"
        case .downloaded:
            if modelManager.activeModelId == model.id { return "in use" }
            return model.isBundled ? "built in" : "on disk"
        }
    }

    // MARK: - Actions

    /// A model on disk is used right away; one downloading is used once it finishes;
    /// any other gets an offer to download it.
    private func pick(_ model: KnownWhisperModel) {
        confirmingDelete = nil
        switch modelManager.downloadStates[model.id] ?? .notDownloaded {
        case .downloaded:
            chosenId = nil
            modelManager.activateWhenDownloaded(nil)
            modelManager.setActiveModel(model)
        case .downloading:
            chosenId = nil
            modelManager.activateWhenDownloaded(model)
        case .notDownloaded, .failed:
            chosenId = model.id
            modelManager.activateWhenDownloaded(nil)
        }
    }

    private func download(_ model: KnownWhisperModel, andUse use: Bool) {
        confirmingDelete = nil
        if use { chosenId = nil }
        modelManager.downloadModel(model, activateOnCompletion: use)
    }

    private func cancelDownload(_ model: KnownWhisperModel) {
        modelManager.cancelDownload(model)
        chosenId = nil
    }

    private func askToDelete(_ model: KnownWhisperModel) {
        // One inline prompt at a time.
        chosenId = nil
        confirmingDelete = model.id
    }

    private func delete(_ model: KnownWhisperModel) {
        let wasInUse = modelManager.activeModelId == model.id
        confirmingDelete = nil
        do {
            try modelManager.deleteModel(model)
        } catch {
            dashboard.showToast(Text("Couldn't delete \(model.fullName): \(error.localizedDescription)"))
            return
        }
        var note = Text("Deleted ")
            + Text(model.fullName).font(.sans(14, .bold))
            + Text(" · \(Ink.formatBytes(model.approximateBytes)) freed")
        if wasInUse, let fallback = KnownWhisperModel.fallback {
            note = note + Text(" · now using \(fallback.fullName)")
            if let engine = SpeechEngine.all.first(where: { $0.models.contains(fallback) }) {
                openEngines.insert(engine.id)
            }
        }
        dashboard.showToast(note)
    }
}

/// A 4pt ink download bar along the bottom of a model row.
private struct ProgressTrack: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.fill)
                Capsule()
                    .fill(Ink.ink)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }
}
