import Foundation
import UIKit

class PatchEngine {
    static let shared = PatchEngine()
    
    func findGameContainerPath(bundleID: String) -> String? {
        let parentDir = "/var/mobile/Containers/Data/Application"
        
        // 1. Xin quyền cho thư mục mẹ
        if !wq_grant(parentDir) {
            let msg = "Grant failed for \(parentDir). Hãy kiểm tra App Group hoặc bật VPN."
            print("[PatchEngine] \(msg)")
            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
            return nil
        }
        
        // 2. Lấy danh sách thư mục
        var errorText: NSString? = nil
        guard let uuids = wq_list(parentDir, &errorText) as? [String] else {
            let msg = "wq_list failed: \(errorText ?? "Unknown")"
            print("[PatchEngine] \(msg)")
            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
            return nil
        }
        
        // 3. Quét tìm thư mục chứa file mang tên Bundle ID
        for uuid in uuids {
            let appDir = "\(parentDir)/\(uuid)"
            
            // Kiểm tra xem trong thư mục này có file tên là bundleID không
            // (Cách này lách được lỗi đọc plist của iOS 26+)
            let possibleFile = "\(appDir)/\(bundleID)"
            if FileManager.default.fileExists(atPath: possibleFile) {
                print("[PatchEngine] Tìm thấy game bằng file name: \(appDir)")
                return appDir
            }
            
            // Dự phòng: Nếu file không có, thử dùng wq_get_container_identifier
            if let id = wq_get_container_identifier(appDir), id == bundleID {
                print("[PatchEngine] Tìm thấy game bằng xattr: \(appDir)")
                return appDir
            }
        }
        
        let msg = "Không tìm thấy bundle ID \(bundleID) trong \(uuids.count) thư mục."
        print("[PatchEngine] \(msg)")
        UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
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
                let msg = "Grant thất bại cho \(bundleID) tại \(gameRootPath). Hãy bật VPN hoặc kiểm tra App Group."
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