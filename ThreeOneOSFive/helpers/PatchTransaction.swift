import Foundation

struct PatchTransactionReceipt: Equatable, Identifiable {
    let id: UUID
    let projectID: UUID
    let journalURL: URL
}

enum PatchTransaction {
    private struct Record: Codable {
        let bundleID: String
        let relativePath: String
        let originalExisted: Bool
        let backupFilename: String?
    }

    private struct Journal: Codable {
        let transactionID: UUID
        let projectID: UUID
        let records: [Record]
    }

    static func apply(project: PatchProject, backupRoot: URL, containerResolver: (String) throws -> URL, fileManager: FileManager = .default) throws -> PatchTransactionReceipt {
        var roots: [String: URL] = [:]
        var resolvedRules: [(PatchRule, URL)] = []
        
        for rule in project.rules {
            let root = PatchPathValidator.canonicalFileURL(try containerResolver(rule.bundleID))
            let target = try PatchPathValidator.resolveContainedTargetURL(relativePath: rule.relativePath, containerRoot: root)
            roots[rule.bundleID] = root
            resolvedRules.append((rule, target))
        }
        
        let transactionID = UUID()
        let transDir = backupRoot.appendingPathComponent(transactionID.uuidString)
        try? fileManager.createDirectory(at: transDir, withIntermediateDirectories: true)
        
        var records: [Record] = []
        for (rule, target) in resolvedRules {
            let existed = fileManager.fileExists(atPath: target.path)
            let backupFilename = existed ? "\(rule.id.uuidString).bak" : nil
            
            if let bf = backupFilename { try? fileManager.copyItem(at: target, to: transDir.appendingPathComponent(bf)) }
            try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? rule.replacementData.write(to: target)
            
            records.append(Record(bundleID: rule.bundleID, relativePath: rule.relativePath, originalExisted: existed, backupFilename: backupFilename))
        }
        
        let journal = Journal(transactionID: transactionID, projectID: project.id, records: records)
        let journalURL = transDir.appendingPathComponent("journal.plist")
        try? PropertyListEncoder().encode(journal).write(to: journalURL)
        
        return PatchTransactionReceipt(id: transactionID, projectID: project.id, journalURL: journalURL)
    }

    static func restore(receipt: PatchTransactionReceipt, containerResolver: (String) throws -> URL, fileManager: FileManager = .default) throws {
        guard let data = try? Data(contentsOf: receipt.journalURL),
              let journal = try? PropertyListDecoder().decode(Journal.self, from: data) else { return }
        
        for record in journal.records {
            let root = PatchPathValidator.canonicalFileURL(try containerResolver(record.bundleID))
            let target = try PatchPathValidator.resolveContainedTargetURL(relativePath: record.relativePath, containerRoot: root)
            
            if record.originalExisted, let bf = record.backupFilename {
                let backupFile = receipt.journalURL.deletingLastPathComponent().appendingPathComponent(bf)
                if fileManager.fileExists(atPath: backupFile.path) {
                    try? fileManager.removeItem(at: target)
                    try? fileManager.copyItem(at: backupFile, to: target)
                }
            } else {
                try? fileManager.removeItem(at: target)
            }
        }
    }

    static func latestReceipt(projectID: UUID, backupRoot: URL, fileManager: FileManager = .default) -> PatchTransactionReceipt? {
        let dir = backupRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard let dirs = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for d in dirs {
            let jUrl = d.appendingPathComponent("journal.plist")
            if let data = try? Data(contentsOf: jUrl),
               let journal = try? PropertyListDecoder().decode(Journal.self, from: data) {
                return PatchTransactionReceipt(id: journal.transactionID, projectID: journal.projectID, journalURL: jUrl)
            }
        }
        return nil
    }

    static func requiredBundleIdentifiers(for receipt: PatchTransactionReceipt) throws -> [String] {
        guard let data = try? Data(contentsOf: receipt.journalURL),
              let journal = try? PropertyListDecoder().decode(Journal.self, from: data) else { return [] }
        return Array(Set(journal.records.map { $0.bundleID }))
    }
}