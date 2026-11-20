import Foundation

struct PatchRestoreInspection {
    // Để trống
}

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                backupCenter: nil 
            )
        }
    }

    static func inspectRestore(receipt: PatchTransactionReceipt) throws -> PatchRestoreInspection {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.inspectRestore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
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
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                allowChangedTargets: allowChangedTargets,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
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
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.resetToAppliedState(
                receipt: receipt,
                fallbackProject: project,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
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

    // 👇 ĐÂY LÀ HÀM ĐÃ ĐƯỢC SỬA ĐỂ DÙNG WQACCESS 👇
    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        
        for bundleID in bundleIDs {
            // 1. Dùng hàm findGameContainerPath của PatchEngine để lấy thư mục gốc
            guard let gameRootPath = PatchEngine.shared.findGameContainerPath(bundleID: bundleID) else {
                let msg = "Không tìm thấy container cho \(bundleID) bằng worse_query."
                print(msg)
                UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            
            // 2. Cấp quyền sandbox bằng WQAccess cho thư mục gốc
            let granted = wq_grant(gameRootPath)
            if !granted {
                let msg = "Grant thất bại cho \(bundleID) tại \(gameRootPath)."
                print(msg)
                UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }

            // 3. Lưu path vào roots (dùng thư mục gốc, không phải Documents)
            roots[bundleID] = PatchPathValidator.canonicalFileURL(
                URL(fileURLWithPath: gameRootPath, isDirectory: true)
            )
        }
        return try operation(roots)
    }
}