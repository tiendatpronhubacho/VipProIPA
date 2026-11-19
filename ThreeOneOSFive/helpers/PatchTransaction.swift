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

    static func apply(
        project: PatchProject,
        backupRoot: URL,
        containerResolver: (String) throws -> URL,
        fileManager: FileManager = .default
    ) throws -> PatchTransactionReceipt {
        let transactionID = UUID()
        let transDir = backupRoot.appendingPathComponent(transactionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: transDir, withIntermediateDirectories: true)

        var records: [Record] = []

        for rule in project.rules {
            let root = try containerResolver(rule.bundleID)
            let target = root.appendingPathComponent(rule.relativePath)

            let existed = fileManager.fileExists(atPath: target.path)
            var backupFilename: String? = nil

            if existed {
                let bf = "\(rule.id.uuidString).bak"
                let backupURL = transDir.appendingPathComponent(bf)
                try? fileManager.removeItem(at: backupURL)
                // Bắt buộc phải backup được, nếu lỗi quyền thì throw ra ngoài
                try fileManager.copyItem(at: target, to: backupURL)
                backupFilename = bf
            } else {
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }

            // Ghi dữ liệu patch, nếu lỗi quyền/đầy bộ nhớ thì throw ra ngoài
            try rule.replacementData.write(to: target, options: .atomic)

            records.append(Record(
                bundleID: rule.bundleID,
                relativePath: rule.relativePath,
                originalExisted: existed,
                backupFilename: backupFilename
            ))
        }

        let journal = Journal(transactionID: transactionID, projectID: project.id, records: records)
        let journalURL = transDir.appendingPathComponent("journal.plist")
        let encoded = try PropertyListEncoder().encode(journal)
        try encoded.write(to: journalURL)

        return PatchTransactionReceipt(id: transactionID, projectID: project.id, journalURL: journalURL)
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        containerResolver: (String) throws -> URL,
        fileManager: FileManager = .default
    ) throws {
        guard let data = try? Data(contentsOf: receipt.journalURL),
              let journal = try? PropertyListDecoder().decode(Journal.self, from: data) else {
            throw PatchPackageError.invalidProject
        }

        for record in journal.records {
            let root = try containerResolver(record.bundleID)
            let target = root.appendingPathComponent(record.relativePath)

            if record.originalExisted, let bf = record.backupFilename {
                let backupURL = receipt.journalURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(bf)
                if fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.removeItem(at: target)
                    try fileManager.copyItem(at: backupURL, to: target)
                }
            } else {
                try? fileManager.removeItem(at: target)
            }
        }
    }

    static func latestReceipt(
        projectID: UUID,
        backupRoot: URL,
        fileManager: FileManager = .default
    ) -> PatchTransactionReceipt? {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var result: PatchTransactionReceipt?
        var newestDate: Date = .distantPast

        for dir in dirs {
            let journalURL = dir.appendingPathComponent("journal.plist")
            guard let data = try? Data(contentsOf: journalURL),
                  let journal = try? PropertyListDecoder().decode(Journal.self, from: data),
                  journal.projectID == projectID else { continue }
            
            let modDate = (try? dir.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if modDate > newestDate {
                newestDate = modDate
                result = PatchTransactionReceipt(
                    id: journal.transactionID,
                    projectID: journal.projectID,
                    journalURL: journalURL
                )
            }
        }
        return result
    }

    static func requiredBundleIdentifiers(for receipt: PatchTransactionReceipt) throws -> [String] {
        guard let data = try? Data(contentsOf: receipt.journalURL),
              let journal = try? PropertyListDecoder().decode(Journal.self, from: data) else {
            throw PatchPackageError.invalidProject
        }
        return Array(Set(journal.records.map { $0.bundleID }))
    }
}