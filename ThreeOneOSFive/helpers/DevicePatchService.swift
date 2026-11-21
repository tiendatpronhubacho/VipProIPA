import Foundation
import UIKit

class PatchEngine {
    static let shared = PatchEngine()
    
    func findGameContainerPath(bundleID: String) -> String? {
        let parentDir = "/var/mobile/Containers/Data/Application"
        
        // 1. Xin quyền cho thư mục mẹ
        _ = wq_grant(parentDir)
        
        // 2. Lấy danh sách thư mục
        guard let uuids = wq_list(parentDir, nil) as? [String] else {
            return nil
        }
        
        for uuid in uuids {
            let appDir = "\(parentDir)/\(uuid)"
            
            // Lấy tên app thông qua metadata (cách app trên ảnh làm)
            if let id = getBundleIDFromXattr(appDir) {
                if id == bundleID {
                    return appDir
                }
            }
        }
        return nil
    }

    // Hàm phụ: Đọc thẳng Bundle ID từ file metadata của iOS
    private func getBundleIDFromXattr(_ path: String) -> String? {
        // Cố gắng đọc thông qua API của Objective-C
        if let identifier = wq_get_container_identifier(path) {
            return identifier as String
        }
        
        // Nếu hàm C không chạy, thử dùng cách của Foundation
        let metadataPath = "\(path)/.com.apple.mobile_container_manager.metadata.plist"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return plist["MCMMetadataIdentifier"] as? String
        }
        
        return nil
    }
    
    func grantAccessToContainer(_ containerPath: String) -> Bool {
        let rootGranted = wq_grant(containerPath)
        let subDirs = ["Documents", "Library", "tmp", "Library/Caches", "Library/Preferences"]
        for sub in subDirs {
            let path = "\(containerPath)/\(sub)"
            _ = wq_grant(path) 
        }
        return rootGranted
    }
}

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

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        
        for bundleID in bundleIDs {
            guard let gameRootPath = PatchEngine.shared.findGameContainerPath(bundleID: bundleID) else {
                let msg = "Không tìm thấy container cho \(bundleID) bằng worse_query."
                print(msg)
                UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            
            let granted = PatchEngine.shared.grantAccessToContainer(gameRootPath)
            if !granted {
                let msg = "Grant thất bại cho \(bundleID) tại \(gameRootPath)."
                print(msg)
                UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }

            roots[bundleID] = PatchPathValidator.canonicalFileURL(
                URL(fileURLWithPath: gameRootPath, isDirectory: true)
            )
        }
        return try operation(roots)
    }
}