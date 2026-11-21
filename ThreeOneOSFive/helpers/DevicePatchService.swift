import Foundation
import UIKit

class PatchEngine {
    static let shared = PatchEngine()
    
    func findGameContainerPath(bundleID: String) -> String? {
        let parentDir = "/var/mobile/Containers/Data/Application"
        
        if !wq_grant(parentDir) {
            let msg = "Lỗi: Không thể xin quyền App Group. Hãy bật VPN, hoặc cài bằng TrollStore nếu iOS 26+"
            UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
            return nil
        }
        
        var errorText: NSString? = nil
        guard let uuids = wq_list(parentDir, &errorText) else {
            UserDefaults.standard.set("Lỗi: Không thể đọc danh sách thư mục.", forKey: "debug_bootstrap_error")
            return nil
        }
        
        for uuid in uuids {
            let appDir = "\(parentDir)/\(uuid)"
            if let id = wq_get_container_identifier(appDir), id == bundleID {
                return appDir
            }
        }
        return nil
    }
}

struct PatchRestoreInspection {}

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
        var grants: [Int64] = []
        defer {
            for grant in grants { SandboxAccess.release(grant) }
        }

        for bundleID in bundleIDs {
            var finalPath: String? = nil
            
            // 1. Thử dùng ContainerStore (BadQuery/Kernel)
            if let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID) {
                finalPath = path
                // Nếu là kernel, không cần lưu grant vì nó trả về -1
                if SandboxAccess.backend != .kernel {
                    let handle = SandboxAccess.grant(path: path, writable: true)
                    if handle >= 0 { grants.append(handle) }
                }
            }
            
            // 2. Nếu ContainerStore thất bại, thử dùng WQFiles (worseQuery)
            if finalPath == nil {
                let version = ProcessInfo.processInfo.operatingSystemVersion
                let isWorseQueryOS = (version.majorVersion == 26 && version.minorVersion >= 7) || version.majorVersion >= 27
                
                if isWorseQueryOS {
                    if let wqPath = PatchEngine.shared.findGameContainerPath(bundleID: bundleID) {
                        if wq_grant(wqPath) {
                            finalPath = wqPath
                            let currentGrant = SandboxAccess.grant(path: wqPath, writable: true)
                            if currentGrant >= 0 { grants.append(currentGrant) }
                        }
                    }
                }
            }
            
            guard let gameRootPath = finalPath else {
                let msg = "Không thể lấy quyền truy cập game \(bundleID)."
                UserDefaults.standard.set(msg, forKey: "debug_bootstrap_error")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }

            roots[bundleID] = PatchPathValidator.canonicalFileURL(
                URL(fileURLWithPath: gameRootPath, isDirectory: true)
            )
        }
        return try operation(roots)
    }