import Foundation
import CryptoKit

struct PatchTransactionReceipt: Equatable, Identifiable {
    let id: UUID
    let projectID: UUID
    let journalURL: URL
}

enum PatchTransaction {
    private struct Record: Codable {
        let ruleID: UUID
        let bundleID: String
        let relativePath: String
        let originalExisted: Bool
        let backupFilename: String?
    }

    private struct Journal: Codable {
        let transactionID: UUID
        let projectID: UUID
        let createdAt: Date
        var status: String
        let records: [Record]
    }

    private static let journalFilename = "journal.plist"

    // Hàm Apply (Bật Mod)
    static func apply(
        project: PatchProject,
        backupRoot: URL,
        containerResolver: (String) throws -> URL,
        fileManager: FileManager = .default
    ) throws -> PatchTransactionReceipt {
        var roots: [String: URL] = [:]
        var resolvedRules: [(PatchRule, URL, URL)] = []

        for rule in project.rules {
            let root = PatchPathValidator.canonicalFileURL(try containerResolver(rule.bundleID))
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: rule.relativePath,
                containerRoot: root
            )
            roots[rule.bundleID] = root
            resolvedRules.append((rule, root, target))
        }

        let transactionID = UUID()
        let transactionDirectory = backupRoot
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
            .appendingPathComponent(transactionID.uuidString, isDirectory: true)
        
        try? fileManager.createDirectory(at: transactionDirectory, withIntermediateDirectories: true)

        var records: [Record] = []
        for (rule, _, target) in resolvedRules {
            let existed = fileManager.fileExists(atPath: target.path)
            let backupFilename = existed ? "\(rule.id.uuidString).original" : nil
            if let backupFilename {
                let backupURL = transactionDirectory.appendingPathComponent(backupFilename)
                try? fileManager.copyItem(at: target, to: backupURL)
            }
            records.append(Record(
                ruleID: rule.id,
                bundleID: rule.bundleID,
                relativePath: rule.relativePath,
                originalExisted: existed,
                backupFilename: backupFilename
            ))
        }

        let journalURL = transactionDirectory.appendingPathComponent(journalFilename)
        let journal = Journal(
            transactionID: transactionID,
            projectID: project.id,
            createdAt: Date(),
            status: "applied",
            records: records
        )
        try writeJournal(journal, to: journalURL)

        // Thực hiện ghi file (Ghi đè)
        for (rule, _, target) in resolvedRules {
            let dir = target.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try rule.replacementData.write(to: target)
        }

        return PatchTransactionReceipt(id: transactionID, projectID: project.id, journalURL: journalURL)
    }

    // Hàm Restore (Tắt Mod)
    static func restore(
        receipt: PatchTransactionReceipt,
        containerResolver: (String) throws -> URL,
        fileManager: FileManager = .default
    ) throws {
        let journal = try readJournal(receipt.journalURL)
        
        var roots: [String: URL] = [:]
        for record in journal.records where roots[record.bundleID] == nil {
            let root = PatchPathValidator.canonicalFileURL(try containerResolver(record.bundleID))
            roots[record.bundleID] = root
        }

        for record in journal.records.reversed() {
            guard let root = roots[record.bundleID] else { continue }
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: record.relativePath,
                containerRoot: root
            )

            if record.originalExisted {
                if let backupFilename = record.backupFilename {
                    let backup = receipt.journalURL.deletingLastPathComponent().appendingPathComponent(backupFilename)
                    if fileManager.fileExists(atPath: backup.path) {
                        try? fileManager.removeItem(at: target)
                        try? fileManager.copyItem(at: backup, to: target)
                    }
                }
            } else {
                if fileManager.fileExists(atPath: target.path) {
                    try? fileManager.removeItem(at: target)
                }
            }
        }
    }

    // Lấy receipt mới nhất
    static func latestReceipt(
        projectID: UUID,
        backupRoot: URL,
        fileManager: FileManager = .default
    ) -> PatchTransactionReceipt? {
        let projectDirectory = backupRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return directories.compactMap { directory -> (Journal, URL)? in
            let url = directory.appendingPathComponent(journalFilename)
            guard let journal = try? readJournal(url),
                  journal.status == "applied" else { return nil }
            return (journal, url)
        }
        .sorted { $0.0.createdAt > $1.0.createdAt }
        .first
        .map {
            PatchTransactionReceipt(
                id: $0.0.transactionID,
                projectID: $0.0.projectID,
                journalURL: $0.1
            )
        }
    }

    static func requiredBundleIdentifiers(for receipt: PatchTransactionReceipt) throws -> [String] {
        let journal = try readJournal(receipt.journalURL)
        var seen = Set<String>()
        return journal.records.map(\.bundleID).compactMap { bundleID in
            seen.insert(bundleID).inserted ? bundleID : nil
        }
    }

    private static func writeJournal(_ journal: Journal, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(journal).write(to: url, options: .atomic)
    }

    private static func readJournal(_ url: URL) throws -> Journal {
        try PropertyListDecoder().decode(Journal.self, from: Data(contentsOf: url))
    }
}