import Foundation

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

/// Manages whisper.cpp model files: the bundled base model and user-downloaded models
/// stored in ~/Library/Application Support/SHH/models/.
final class ModelManager: @unchecked Sendable {
    static let shared = ModelManager()

    static let bundledModelName = "ggml-base.bin"

    private let userModelsDirectoryName = "models"
    private let appSupportDirectoryName = "SHH"

    private(set) var activeModelPath: String?

    /// The path to ~/Library/Application Support/SHH/models/
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
        activeModelPath = bundledModelPath()
    }

    /// Creates the ~/Library/Application Support/SHH/models/ directory if it doesn't exist.
    func ensureUserModelsDirectoryExists() throws {
        let dir = userModelsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true
                )
            } catch {
                throw ModelError.directoryCreationFailed(path: dir.path, underlying: error)
            }
        }
    }

    /// Returns the path to the bundled base model, or nil if it's missing.
    func bundledModelPath() -> String? {
        Bundle.main.path(forResource: "ggml-base", ofType: "bin")
    }

    /// Resolves the active model path: user-selected model if available, otherwise the bundled base.
    /// Returns nil only if both are unavailable.
    func resolveActiveModelPath() -> String? {
        if let active = activeModelPath,
           FileManager.default.fileExists(atPath: active) {
            return active
        }
        // Fall back to bundled model
        let bundled = bundledModelPath()
        activeModelPath = bundled
        return bundled
    }

    /// Sets a user-selected model as the active model.
    /// The model must exist in the user models directory.
    func setActiveModel(name: String) throws {
        let modelPath = userModelsDirectory.appendingPathComponent(name).path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw ModelError.modelNotFound(name: name)
        }
        activeModelPath = modelPath
    }

    /// Resets the active model to the bundled base model.
    func resetToDefaultModel() {
        activeModelPath = bundledModelPath()
    }

    /// Lists all available models (bundled + user-downloaded).
    func availableModels() -> [WhisperModel] {
        var models: [WhisperModel] = []

        // Bundled model
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

        // User models
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

    /// Deletes a user-downloaded model. The bundled base model cannot be deleted.
    func deleteModel(_ model: WhisperModel) throws {
        guard !model.isBundled else {
            throw ModelError.cannotDeleteBundledModel
        }
        try FileManager.default.removeItem(atPath: model.path)

        // If this was the active model, reset to default
        if activeModelPath == model.path {
            resetToDefaultModel()
        }
    }
}
