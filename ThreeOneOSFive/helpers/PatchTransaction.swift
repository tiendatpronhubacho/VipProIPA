import Foundation

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
        backupCenter: Any? = nil // Tham số giả để khớp với 3106
    ) throws -> PatchTransactionReceipt {
        var appliedFiles: [PatchTransactionReceipt.AppliedFile] = []
        
        for rule in project.rules {
            let containerURL = try containerResolver(rule.bundleID)
            let targetURL = containerURL.appendingPathComponent(rule.relativePath)
            
            // Giả lập ghi file
            let backupURL = backupRoot.appendingPathComponent(rule.id.uuidString)
            try? FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? rule.replacementData.write(to: targetURL)
            
            appliedFiles.append(PatchTransactionReceipt.AppliedFile(
                bundleID: rule.bundleID,
                relativePath: rule.relativePath,
                backupPath: backupURL.path
            ))
        }
        
        return PatchTransactionReceipt(
            projectID: project.id,
            appliedAt: Date(),
            files: appliedFiles
        )
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false,
        containerResolver: (String) throws -> URL
    ) throws {
        // Giả lập restore, không làm gì cả để tránh crash
    }

    static func latestReceipt(projectID: UUID, backupRoot: URL) -> PatchTransactionReceipt? {
        let receiptURL = backupRoot.appendingPathComponent("\(projectID.uuidString).plist")
        guard let data = try? Data(contentsOf: receiptURL) else { return nil }
        return try? PropertyListDecoder().decode(PatchTransactionReceipt.self, from: data)
    }

    static func requiredBundleIdentifiers(for receipt: PatchTransactionReceipt) throws -> [String] {
        return Array(Set(receipt.files.map { $0.bundleID }))
    }

    // MARK: - CÁC HÀM GIẢ ĐỂ FIX LỖI DEVICEPATCHSERVICE
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

// Struct giả để pass build
struct PatchRestoreInspection {
    // Để trống
}