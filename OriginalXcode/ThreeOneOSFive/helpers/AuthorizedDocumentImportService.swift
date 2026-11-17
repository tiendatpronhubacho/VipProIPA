import Foundation

struct AuthorizedDocumentImportResult: Equatable {
    let importedURLs: [URL]
    let failedNames: [String]
}

enum AuthorizedDocumentImportError: Error, LocalizedError {
    case noDocuments
    case cannotCreateDestination
    case unsupportedItem

    var errorDescription: String? {
        switch self {
        case .noDocuments: return "No documents were selected."
        case .cannotCreateDestination: return "The app could not create its authorized-imports folder."
        case .unsupportedItem: return "Only regular files can be imported."
        }
    }
}

enum AuthorizedDocumentImportService {
    /// Imports only URLs returned by the system document picker. Files are
    /// copied into this app's Documents directory, so later operations never
    /// need to guess or traverse another app's private container.
    static func importDocuments(_ urls: [URL]) throws -> AuthorizedDocumentImportResult {
        guard !urls.isEmpty else { throw AuthorizedDocumentImportError.noDocuments }
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destination = documents.appendingPathComponent("Authorized Imports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } catch {
            throw AuthorizedDocumentImportError.cannotCreateDestination
        }

        var imported: [URL] = []
        var failed: [String] = []
        for source in urls {
            let didStart = source.startAccessingSecurityScopedResource()
            defer { if didStart { source.stopAccessingSecurityScopedResource() } }
            do {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    failed.append(source.lastPathComponent)
                    continue
                }
                let safeName = source.lastPathComponent
                    .replacingOccurrences(of: "/", with: "_")
                var target = destination.appendingPathComponent(safeName)
                if FileManager.default.fileExists(atPath: target.path) {
                    let stem = target.deletingPathExtension().lastPathComponent
                    let ext = target.pathExtension
                    let unique = UUID().uuidString.prefix(8)
                    target = destination.appendingPathComponent(
                        ext.isEmpty ? "\(stem)-\(unique)" : "\(stem)-\(unique).\(ext)"
                    )
                }
                try FileManager.default.copyItem(at: source, to: target)
                imported.append(target)
            } catch {
                failed.append(source.lastPathComponent)
            }
        }
        return AuthorizedDocumentImportResult(importedURLs: imported, failedNames: failed)
    }
}
