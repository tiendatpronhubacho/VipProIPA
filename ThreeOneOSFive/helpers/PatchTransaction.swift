import Foundation

private enum PatchTransactionError: Error, LocalizedError {
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let path):
            return "Patch verification failed: the file contents did not match the replacement data at \(path)"
        }
    }
}

struct PatchTransactionReceipt: Codable, Hashable {
    let projectID: UUID
    let appliedAt: Date
    let files: [AppliedFile]
    
    struct AppliedFile: Codable, Hashable {
        let bundleID: String
        let relativePath: String
        let backupPath: String
    }
}

enum PatchTransaction {
    static func apply(
        project: PatchProject,
        backupRoot: URL,
        containerResolver: (String) throws -> URL,
        backupCenter: Any? = nil
    ) throws -> PatchTransactionReceipt {
        var appliedFiles: [PatchTransactionReceipt.AppliedFile] = []
        
        for rule in project.rules {
            let containerURL = try containerResolver(rule.bundleID)
            let targetURL = containerURL.appendingPathComponent(rule.relativePath)
            let targetDir = targetURL.deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at: targetDir,
                withIntermediateDirectories: true
            )

            let backupURL = backupRoot.appendingPathComponent(rule.id.uuidString)
            try FileManager.default.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let targetExisted = FileManager.default.fileExists(atPath: targetURL.path)
            if targetExisted {
                // Never proceed with a destructive write if the backup failed.
                try FileManager.default.copyItem(at: targetURL, to: backupURL)
            }

            do {
                try rule.replacementData.write(to: targetURL, options: .atomic)

                // Confirm the actual target bytes before reporting success.
                let writtenData = try Data(contentsOf: targetURL, options: .mappedIfSafe)
                guard writtenData == rule.replacementData else {
                    throw PatchTransactionError.verificationFailed(targetURL.path)
                }
            } catch {
                // Best-effort rollback of the current target if writing or
                // read-back verification fails.
                do {
                    if targetExisted, FileManager.default.fileExists(atPath: backupURL.path) {
                        if FileManager.default.fileExists(atPath: targetURL.path) {
                            try FileManager.default.removeItem(at: targetURL)
                        }
                        try FileManager.default.copyItem(at: backupURL, to: targetURL)
                    } else if !targetExisted, FileManager.default.fileExists(atPath: targetURL.path) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                } catch {
                    log("patch: rollback failed target=\(targetURL.path) error=\(error)")
                }
                log("patch: write/verify failed target=\(targetURL.path) error=\(error)")
                throw error
            }

            appliedFiles.append(PatchTransactionReceipt.AppliedFile(
                bundleID: rule.bundleID,
                relativePath: rule.relativePath,
                backupPath: backupURL.path
            ))
        }
        
        let receipt = PatchTransactionReceipt(
            projectID: project.id,
            appliedAt: Date(),
            files: appliedFiles
        )
        
        let receiptURL = backupRoot.appendingPathComponent("\(project.id.uuidString).plist")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(receipt)
        try data.write(to: receiptURL, options: .atomic)

        return receipt
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false,
        containerResolver: (String) throws -> URL
    ) throws {
        for file in receipt.files {
            let containerURL = try containerResolver(file.bundleID)
            let targetURL = containerURL.appendingPathComponent(file.relativePath)
            let backupURL = URL(fileURLWithPath: file.backupPath)
            
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
                try? FileManager.default.copyItem(at: backupURL, to: targetURL)
                try? FileManager.default.removeItem(at: backupURL)
            } else {
                try? FileManager.default.removeItem(at: targetURL)
            }
        }
        
        if let backupRoot = try? PatchProjectLibrary.backupRootURL() {
            let receiptURL = backupRoot.appendingPathComponent("\(receipt.projectID.uuidString).plist")
            try? FileManager.default.removeItem(at: receiptURL)
        }
    }

    static func latestReceipt(projectID: UUID, backupRoot: URL) -> PatchTransactionReceipt? {
        let receiptURL = backupRoot.appendingPathComponent("\(projectID.uuidString).plist")
        guard let data = try? Data(contentsOf: receiptURL) else { return nil }
        return try? PropertyListDecoder().decode(PatchTransactionReceipt.self, from: data)
    }

    static func requiredBundleIdentifiers(for receipt: PatchTransactionReceipt) throws -> [String] {
        return Array(Set(receipt.files.map { $0.bundleID }))
    }

    static func inspectRestore(
        receipt: PatchTransactionReceipt,
        containerResolver: (String) throws -> URL
    ) throws -> PatchRestoreInspection {
        return PatchRestoreInspection()
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        fallbackProject: PatchProject,
        containerResolver: (String) throws -> URL
    ) throws {
        // Không làm gì
    }
}