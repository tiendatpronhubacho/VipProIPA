import Foundation
import UIKit

class PatchEngine {
    static let shared = PatchEngine()
    
    // Hàm quét động bằng WQFiles (Dành cho iOS 26+)
    func findGameContainerPath(bundleID: String) -> String? {
        let parentDir = "/var/mobile/Containers/Data/Application"
        
        if !wq_grant(parentDir) {
            let msg = "Lỗi: Không thể xin quyền App Group. (Hãy bật VPN, hoặc bạn đang dùng Cert thường. Hãy cài bằng TrollStore nếu iOS 26+)"
            print("[PatchEngine] \(msg)")
            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
            return nil
        }
        
        var errorText: NSString? = nil
        guard let uuids = wq_list(parentDir, &errorText) as? [String] else {
            let msg = "Lỗi: Không thể đọc danh sách thư mục. \(errorText ?? "")"
            print("[PatchEngine] \(msg)")
            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
            return nil
        }
        
        for uuid in uuids {
            let appDir = "\(parentDir)/\(uuid)"
            let possibleFile = "\(appDir)/\(bundleID)"
            if FileManager.default.fileExists(atPath: possibleFile) {
                return appDir
            }
            if let id = wq_get_container_identifier(appDir), id == bundleID {
                return appDir
            }
        }
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
            
            // 2. NẾU CƠ CHẾ CŨ THẤT BẠI, CHUYỂN SANG DÙNG WQFILES
            if finalPath == nil {
                let version = ProcessInfo.processInfo.operatingSystemVersion
                let isWorseQueryOS = (version.majorVersion == 26 && version.minorVersion >= 7) || version.majorVersion >= 27
                
                if isWorseQueryOS {
                    if let wqPath = PatchEngine.shared.findGameContainerPath(bundleID: bundleID) {
                        if wq_grant(wqPath) {
                            finalPath = wqPath
                        } else {
                            let msg = "WQFiles: Grant thất bại. Bạn cần bật VPN hoặc cài bằng TrollStore (nếu iOS 26+)."
                            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                        }
                    }
                } else {
                    // Nếu là iOS 26.6.1 trở xuống, không dùng WQFiles, báo lỗi trực tiếp để fallback.
                    log("patch: iOS < 26.7 không dùng WQFiles, fallback to bad_query.")
                }
            }
            
            // 3. NẾU CẢ 2 ĐỀU THẤT BẠI -> BÁO LỖI
            guard let gameRootPath = finalPath else {
                let msg = "Không thể lấy quyền truy cập game \(bundleID). Hãy xem hướng dẫn."
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