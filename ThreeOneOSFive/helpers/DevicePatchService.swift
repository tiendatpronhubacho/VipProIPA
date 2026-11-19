import Foundation

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        var bundleIDs = project.allBundleIdentifiers
        bundleIDs = bundleIDs.map { fixBundleID($0) }
        
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    let fixedID = fixBundleID(bundleID)
                    if let root = roots[fixedID] { return root }
                    if let firstRoot = roots.values.first { return firstRoot }
                    throw PatchPackageError.targetAppUnavailable(bundleID)
                }
            )
        }
    }

    static func restore(receipt: PatchTransactionReceipt) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    let fixedID = fixBundleID(bundleID)
                    guard let root = roots[fixedID] ?? roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    private static func fixBundleID(_ bundleID: String) -> String {
        let lower = bundleID.lowercased()
        if lower.contains("ffvn") || lower.contains("freefire") || lower.contains("garena") { return "com.garena.ffvn" }
        return bundleID
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        var grants: [Int64] = []
        defer { for grant in grants { SandboxAccess.release(grant) } }

        for bundleID in bundleIDs {
            var path = ContainerStore.resolveAppContainerPath(bundleID: bundleID)
            guard let validPath = path, ContainerStore.isApplicationContainerPath(validPath) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            let grant = ContainerStore.grantContainerAccess(validPath)
            if grant >= 0 { grants.append(grant) }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: validPath, isDirectory: true))
        }
        return try operation(roots)
    }
}