import Foundation
import Observation

// MARK: - KnownWhisperModel

/// Represents an entry in the OpenAI Whisper model catalog.
struct KnownWhisperModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let fileName: String
    let approximateBytes: Int64
    let downloadURL: URL
    /// True for the single most capable model (large-v3).
    let isMostPowerful: Bool

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }

    /// Full OpenAI Whisper model catalog ordered from most to least capable.
    static let catalog: [KnownWhisperModel] = [
        .init(
            id: "large-v3",
            displayName: "Large v3",
            description: "Highest accuracy",
            fileName: "ggml-large-v3.bin",
            approximateBytes: 3_094_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            isMostPowerful: true
        ),
        .init(
            id: "medium",
            displayName: "Medium",
            description: "Balanced accuracy & speed",
            fileName: "ggml-medium.bin",
            approximateBytes: 1_528_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            isMostPowerful: false
        ),
        .init(
            id: "small",
            displayName: "Small",
            description: "Good accuracy, faster",
            fileName: "ggml-small.bin",
            approximateBytes: 466_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            isMostPowerful: false
        ),
        .init(
            id: "base",
            displayName: "Base",
            description: "Fast, lightweight",
            fileName: "ggml-base.bin",
            approximateBytes: 142_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            isMostPowerful: false
        ),
        .init(
            id: "tiny",
            displayName: "Tiny",
            description: "Fastest, lower accuracy",
            fileName: "ggml-tiny.bin",
            approximateBytes: 75_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
            isMostPowerful: false
        ),
    ]
}

// MARK: - ModelDownloadState

enum ModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(message: String)
}

// MARK: - ModelError

enum ModelError: Error, LocalizedError {
    case bundledModelMissing
    case modelNotFound(name: String)
    case directoryCreationFailed(path: String, underlying: Error)
    case cannotDeleteBundledModel

    var errorDescription: String? {
        switch self {
        case .bundledModelMissing:
            return "Bundled base model is missing from app resources"
        case .modelNotFound(let name):
            return "Model not found: \(name)"
        case .directoryCreationFailed(let path, let err):
            return "Failed to create models directory at \(path): \(err.localizedDescription)"
        case .cannotDeleteBundledModel:
            return "The bundled base model cannot be deleted"
        }
    }
}

// MARK: - WhisperModel (legacy)

struct WhisperModel: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let isBundled: Bool
    let fileSize: UInt64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

// MARK: - ModelManager

/// Manages the OpenAI Whisper model catalog: tracks which models are downloaded,
/// drives background downloads with progress, and exposes the active model path
/// for TranscriptionPipeline.
@Observable
final class ModelManager: @unchecked Sendable {
    static let shared = ModelManager()

    static let bundledModelName = "ggml-base.bin"

    private static let activeModelIdKey = "activeWhisperModelId"
    private static let hasAutoDownloadedLargeKey = "hasAutoDownloadedLargeModel"

    private let userModelsDirectoryName = "models"
    private let appSupportDirectoryName = "SHH"

    /// The ID of the currently selected model (persisted to UserDefaults).
    private(set) var activeModelId: String

    /// Per-model download states, keyed by KnownWhisperModel.id.
    private(set) var downloadStates: [String: ModelDownloadState] = [:]

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadObservations: [String: NSKeyValueObservation] = [:]

    /// Path to ~/Library/Application Support/SHH/models/
    var userModelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent(appSupportDirectoryName)
            .appendingPathComponent(userModelsDirectoryName)
    }

    private init() {
        let savedId = UserDefaults.standard.string(forKey: Self.activeModelIdKey)
        activeModelId = savedId ?? KnownWhisperModel.catalog.first(where: { $0.isMostPowerful })?.id ?? "base"

        for model in KnownWhisperModel.catalog {
            downloadStates[model.id] = checkIsOnDisk(model) ? .downloaded : .notDownloaded
        }

        // Automatically download the most powerful model on first launch.
        if !UserDefaults.standard.bool(forKey: Self.hasAutoDownloadedLargeKey) {
            UserDefaults.standard.set(true, forKey: Self.hasAutoDownloadedLargeKey)
            if let largeModel = KnownWhisperModel.catalog.first(where: { $0.isMostPowerful }),
               !checkIsOnDisk(largeModel) {
                startDownload(largeModel)
            }
        }
    }

    // MARK: - Path Resolution

    /// Returns the path to the bundled base model, or nil if missing.
    func bundledModelPath() -> String? {
        Bundle.main.path(forResource: "ggml-base", ofType: "bin")
    }

    /// Returns the file-system path for the active model, falling back to the
    /// bundled base if the selected model is not on disk.
    func resolveActiveModelPath() -> String? {
        if let model = KnownWhisperModel.catalog.first(where: { $0.id == activeModelId }) {
            let userPath = userModelsDirectory.appendingPathComponent(model.fileName).path
            if FileManager.default.fileExists(atPath: userPath) { return userPath }
            if model.id == "base", let bundled = bundledModelPath() { return bundled }
        }
        return bundledModelPath()
    }

    // MARK: - Model Status

    func isModelOnDisk(_ model: KnownWhisperModel) -> Bool {
        checkIsOnDisk(model)
    }

    private func checkIsOnDisk(_ model: KnownWhisperModel) -> Bool {
        if model.id == "base", bundledModelPath() != nil { return true }
        let path = userModelsDirectory.appendingPathComponent(model.fileName).path
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Model Selection

    /// Sets a downloaded model as active. No-op if the model is not on disk.
    func setActiveModel(_ model: KnownWhisperModel) {
        guard checkIsOnDisk(model) else { return }
        activeModelId = model.id
        UserDefaults.standard.set(model.id, forKey: Self.activeModelIdKey)
    }

    // MARK: - Downloads

    func ensureUserModelsDirectoryExists() throws {
        let dir = userModelsDirectory
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ModelError.directoryCreationFailed(path: dir.path, underlying: error)
        }
    }

    /// Initiates a download for the given model. No-op if already downloaded or in progress.
    func downloadModel(_ model: KnownWhisperModel) {
        switch downloadStates[model.id] ?? .notDownloaded {
        case .downloaded, .downloading(_): return
        case .notDownloaded, .failed(_): startDownload(model)
        }
    }

    /// Cancels an in-progress download and resets the model state to notDownloaded.
    func cancelDownload(_ model: KnownWhisperModel) {
        downloadTasks[model.id]?.cancel()
        cleanupDownloadTracking(modelId: model.id)
        DispatchQueue.main.async { self.downloadStates[model.id] = .notDownloaded }
    }

    private func startDownload(_ model: KnownWhisperModel) {
        try? ensureUserModelsDirectoryExists()
        DispatchQueue.main.async { self.downloadStates[model.id] = .downloading(progress: 0) }

        let task = URLSession.shared.downloadTask(with: model.downloadURL) { [weak self] tempURL, _, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.downloadStates[model.id] = .failed(message: error.localizedDescription)
                    self.cleanupDownloadTracking(modelId: model.id)
                }
                return
            }

            guard let tempURL else {
                DispatchQueue.main.async {
                    self.downloadStates[model.id] = .failed(message: "No file received from server")
                    self.cleanupDownloadTracking(modelId: model.id)
                }
                return
            }

            let destURL = self.userModelsDirectory.appendingPathComponent(model.fileName)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                DispatchQueue.main.async {
                    self.downloadStates[model.id] = .downloaded
                    self.cleanupDownloadTracking(modelId: model.id)
                    if model.isMostPowerful {
                        self.setActiveModel(model)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.downloadStates[model.id] = .failed(message: error.localizedDescription)
                    self.cleanupDownloadTracking(modelId: model.id)
                }
            }
        }

        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadStates[model.id] = .downloading(progress: progress.fractionCompleted)
            }
        }

        downloadTasks[model.id] = task
        downloadObservations[model.id] = observation
        task.resume()
    }

    private func cleanupDownloadTracking(modelId: String) {
        downloadTasks.removeValue(forKey: modelId)
        downloadObservations.removeValue(forKey: modelId)
    }

    // MARK: - Legacy API

    var activeModelPath: String? { resolveActiveModelPath() }

    func resetToDefaultModel() {
        let defaultId = KnownWhisperModel.catalog
            .first(where: { $0.isMostPowerful && checkIsOnDisk($0) })?.id ?? "base"
        activeModelId = defaultId
        UserDefaults.standard.set(defaultId, forKey: Self.activeModelIdKey)
    }

    func availableModels() -> [WhisperModel] {
        var models: [WhisperModel] = []
        if let bundledPath = bundledModelPath() {
            let attrs = try? FileManager.default.attributesOfItem(atPath: bundledPath)
            let size = attrs?[.size] as? UInt64 ?? 0
            models.append(WhisperModel(
                id: "bundled-base",
                name: Self.bundledModelName,
                path: bundledPath,
                isBundled: true,
                fileSize: size
            ))
        }
        let dir = userModelsDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for file in contents where file.hasSuffix(".bin") {
                let fullPath = dir.appendingPathComponent(file).path
                let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath)
                let size = attrs?[.size] as? UInt64 ?? 0
                models.append(WhisperModel(
                    id: "user-\(file)",
                    name: file,
                    path: fullPath,
                    isBundled: false,
                    fileSize: size
                ))
            }
        }
        return models
    }

    func deleteModel(_ model: WhisperModel) throws {
        guard !model.isBundled else { throw ModelError.cannotDeleteBundledModel }
        try FileManager.default.removeItem(atPath: model.path)
        if activeModelPath == model.path { resetToDefaultModel() }
    }
}
