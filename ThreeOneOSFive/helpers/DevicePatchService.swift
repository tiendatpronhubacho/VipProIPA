import Foundation
import UIKit

class PatchEngine {
    static let shared = PatchEngine()
    
    // Hàm quét động bằng WQFiles (Dành cho iOS 26+)
    func findGameContainerPath(bundleID: String) -> String? {
        let parentDir = "/var/mobile/Containers/Data/Application"
        
        // 1. Xin quyền cho thư mục mẹ
        if !wq_grant(parentDir) {
            let msg = "WQFiles: Grant failed for \(parentDir)."
            print("[PatchEngine] \(msg)")
            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
            return nil
        }
        
        // 2. Lấy danh sách thư mục
        var errorText: NSString? = nil
        guard let uuids = wq_list(parentDir, &errorText) as? [String] else {
            let msg = "WQFiles: wq_list failed: \(errorText ?? "Unknown")"
            print("[PatchEngine] \(msg)")
            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
            return nil
        }
        
        // 3. Quét tìm thư mục chứa file mang tên Bundle ID
        for uuid in uuids {
            let appDir = "\(parentDir)/\(uuid)"
            
            let possibleFile = "\(appDir)/\(bundleID)"
            if FileManager.default.fileExists(atPath: possibleFile) {
                print("[PatchEngine] WQFiles: Tìm thấy game bằng file name: \(appDir)")
                return appDir
            }
            
            if let id = wq_get_container_identifier(appDir), id == bundleID {
                print("[PatchEngine] WQFiles: Tìm thấy game bằng xattr: \(appDir)")
                return appDir
            }
        }
        
        let msg = "WQFiles: Không tìm thấy bundle ID \(bundleID) trong \(uuids.count) thư mục."
        print("[PatchEngine] \(msg)")
        UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
        return nil
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

    // 👇 HÀM GỘP: TỰ ĐỘNG CHỌN CƠ CHẾ CŨ HOẶC MỚI 👇
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
            var finalPath: String? = nil
            
            // 1. THỬ DÙNG CƠ CHẾ CŨ (KERNEL EXPLOIT) TRƯỚC
            // Cơ chế này chạy tốt trên iOS 17, 18, và không cần App Group.
            if let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
               ContainerStore.isApplicationContainerPath(path) {
                
                let grant = ContainerStore.grantContainerAccess(path)
                if grant >= 0 {
                    grants.append(grant)
                    finalPath = path
                    print("[PatchService] Dùng Kernel Exploit thành công cho \(bundleID)")
                }
            }
            
            // 2. NẾU CƠ CHẾ CŨ THẤT BẠI (VD: iOS 26+), CHUYỂN SANG DÙNG WQFILES
            if finalPath == nil {
                print("[PatchService] Kernel Exploit thất bại, chuyển sang WQFiles cho \(bundleID)...")
                
                if let wqPath = PatchEngine.shared.findGameContainerPath(bundleID: bundleID) {
                    if wq_grant(wqPath) {
                        finalPath = wqPath
                        print("[PatchService] Dùng WQFiles thành công cho \(bundleID)")
                    } else {
                        let msg = "WQFiles: Grant thất bại tại \(wqPath). Hãy bật VPN hoặc kiểm tra App Group."
                        print(msg)
                        UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                    }
                } else {
                     let msg = "WQFiles: Không tìm thấy đường dẫn game \(bundleID)."
                     print(msg)
                     UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                }
            }
            
            // 3. NẾU CẢ 2 ĐỀU THẤT BẠI -> BÁO LỖI
            guard let gameRootPath = finalPath else {
                let msg = "Không thể lấy quyền truy cập game \(bundleID) bằng mọi cách."
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