import SwiftUI

struct WhisperModelsView: View {
    @State private var modelManager = ModelManager.shared
    @State private var pendingDownloadModel: KnownWhisperModel? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            modelList
        }
        .background(Color.appBackground)
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Whisper")
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

    // MARK: - List

    private var modelList: some View {
        List {
            ForEach(KnownWhisperModel.catalog) { model in
                ModelRow(
                    model: model,
                    state: modelManager.downloadStates[model.id] ?? .notDownloaded,
                    isActive: modelManager.activeModelId == model.id,
                    onActivate: { modelManager.setActiveModel(model) },
                    onDownload: { pendingDownloadModel = model },
                    onCancelDownload: { modelManager.cancelDownload(model) }
                )
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: KnownWhisperModel
    let state: ModelDownloadState
    let isActive: Bool
    let onActivate: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void

    @State private var isRowHovered = false

    private var isDownloaded: Bool {
        if case .downloaded = state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(Font.appBody)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            isDownloaded
                                ? Color.appForeground
                                : Color.appForeground.opacity(0.45)
                        )
                    if isActive {
                        Text("Active")
                            .font(Font.appCaption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.appError)
                            .clipShape(Capsule())
                    }
                    if model.isMostPowerful {
                        Text("BEST")
                            .font(Font.appCaption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appError)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appError.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack(spacing: 8) {
                    Text(model.description)
                        .font(Font.appCaption)
                        .foregroundStyle(
                            isDownloaded
                                ? Color.appForeground.opacity(0.6)
                                : Color.appForeground.opacity(0.35)
                        )
                    Text("·")
                        .font(Font.appCaption)
                        .foregroundStyle(Color.appForeground.opacity(0.3))
                    Text(model.displaySize)
                        .font(Font.appCaption)
                        .foregroundStyle(
                            isDownloaded
                                ? Color.appForeground.opacity(0.6)
                                : Color.appForeground.opacity(0.35)
                        )
                        .monospacedDigit()
                }
            }

            Spacer()

            rowAction
        }
        .padding(20)
        .opacity(isDownloaded ? 1.0 : 0.75)
        .background(
            isRowHovered && isDownloaded
                ? Color.appForeground.opacity(0.08)
                : Color.appForeground.opacity(0.05)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.appForeground.opacity(0.1), lineWidth: 1)
        )
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
    }

    @ViewBuilder
    private var rowAction: some View {
        switch state {
        case .downloaded:
            Toggle("", isOn: Binding(
                get: { isActive },
                set: { newValue in if newValue { onActivate() } }
            ))
            .toggleStyle(AppToggleStyle())
            .labelsHidden()

        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.appError)
                    .frame(width: 72)
                Button(action: onCancelDownload) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appForeground.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            }

        case .notDownloaded, .failed(_):
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.appForeground.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Download \(model.displayName) (\(model.displaySize))")
        }
    }
}
