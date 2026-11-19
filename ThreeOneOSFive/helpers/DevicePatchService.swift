import Foundation

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        var bundleIDs = orderedBundleIdentifiers(in: project)
        
        // [FIX] Tự động sửa lại Bundle ID của Free Fire nếu file patch ghi sai
        bundleIDs = bundleIDs.map { fixBundleID($0) }
        
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    // Map lại một lần nữa để chắc chắn
                    let fixedID = fixBundleID(bundleID)
                    guard let root = roots[fixedID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                backupCenter: .shared
            )
        }
    }

    static func inspectRestore(receipt: PatchTransactionReceipt) throws -> PatchRestoreInspection {
        var bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        bundleIDs = bundleIDs.map { fixBundleID($0) }
        
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.inspectRestore(
                receipt: receipt,
                containerResolver: { bundleID in
                    let fixedID = fixBundleID(bundleID)
                    guard let root = roots[fixedID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false
    ) throws {
        var bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        bundleIDs = bundleIDs.map { fixBundleID($0) }
        
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                allowChangedTargets: allowChangedTargets,
                containerResolver: { bundleID in
                    let fixedID = fixBundleID(bundleID)
                    guard let root = roots[fixedID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        project: PatchProject
    ) throws {
        var bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        bundleIDs = bundleIDs.map { fixBundleID($0) }
        
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.resetToAppliedState(
                receipt: receipt,
                fallbackProject: project,
                containerResolver: { bundleID in
                    let fixedID = fixBundleID(bundleID)
                    guard let root = roots[fixedID] else {
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

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    // HÀM MỚI: Tự động nhận diện Bundle ID thực tế của game
    private static func fixBundleID(_ bundleID: String) -> String {
        let lower = bundleID.lowercased()
        // Nếu là Free Fire VN
        if lower.contains("ffvn") || lower.contains("freefire") || lower.contains("garena") {
            // Kiểm tra xem máy đang cài bản nào
            if ContainerStore.resolveAppContainerPath(bundleID: "com.garena.ffvn") != nil {
                return "com.garena.ffvn"
            } else if ContainerStore.resolveAppContainerPath(bundleID: "com.garena.game.ffvn") != nil {
                return "com.garena.game.ffvn"
            }
        }
        return bundleID
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        var grants: [Int64] = []
        defer {
            for grant in grants { SandboxAccess.release(grant) }
        }

        for bundleID in bundleIDs {
            // Cố gắng lấy đường dẫn
            var path = ContainerStore.resolveAppContainerPath(bundleID: bundleID)
            
            // Nếu không tìm thấy, thử dùng tên Bundle ID khác
            if path == nil {
                let alternateID = bundleID == "com.garena.ffvn" ? "com.garena.game.ffvn" : "com.garena.ffvn"
                path = ContainerStore.resolveAppContainerPath(bundleID: alternateID)
            }

            guard let validPath = path, ContainerStore.isApplicationContainerPath(validPath) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            
            // Cấp quyền (grant) cho đường dẫn này
            let grant = ContainerStore.grantContainerAccess(validPath)
            if grant >= 0 { grants.append(grant) }
            
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: validPath, isDirectory: true))
        }
        return try operation(roots)
    }
}