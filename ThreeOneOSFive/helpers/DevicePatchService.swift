import Foundation

enum DevicePatchService {
    // 1. Hàm Apply: Sử dụng hàm apply gốc của PatchTransaction
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        var bundleIDs = orderedBundleIdentifiers(in: project)
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

    // 2. Hàm Restore: Gọi đúng hàm restore gốc
    static func restore(
        receipt: PatchTransactionReceipt
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    // Bản gốc 3105 không dùng fixBundleID ở hàm restore, nhưng ta thêm vào cho an toàn
                    let fixedID = fixBundleID(bundleID)
                    guard let root = roots[fixedID] ?? roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    // 3. Hàm lấy Receipt mới nhất
    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    // Hàm phụ lấy toàn bộ BundleID
    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    // Hàm tự động lách lỗi tên game (garena/ffvn)
    private static func fixBundleID(_ bundleID: String) -> String {
        let lower = bundleID.lowercased()
        if lower.contains("ffvn") || lower.contains("freefire") || lower.contains("garena") {
            return "com.garena.ffvn"
        }
        return bundleID
    }

    // Hàm phân giải Container (tìm thư mục game)
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
            var path = ContainerStore.resolveAppContainerPath(bundleID: bundleID)
            
            if path == nil && bundleID.contains("garena") {
                if let foundPath = findGameFolderByKeyword(keyword: "garena") {
                    path = foundPath
                } else if let foundPath = findGameFolderByKeyword(keyword: "ffvn") {
                    path = foundPath
                }
            }

            guard let validPath = path, ContainerStore.isApplicationContainerPath(validPath) else {
                if let genericPath = ContainerStore.enumerateDirectories(path: ContainerStore.appDataRoot).first {
                     let grant = ContainerStore.grantContainerAccess(genericPath)
                     if grant >= 0 { grants.append(grant) }
                     roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: genericPath, isDirectory: true))
                     continue
                }
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            
            let grant = ContainerStore.grantContainerAccess(validPath)
            if grant >= 0 { grants.append(grant) }
            
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: validPath, isDirectory: true))
        }
        return try operation(roots)
    }
    
    // Hàm phụ quét từ khóa thư mục
    private static func findGameFolderByKeyword(keyword: String) -> String? {
        let dirs = ContainerStore.enumerateDirectories(path: ContainerStore.appDataRoot)
        for dir in dirs {
            let metadataPath = (dir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let id = plist["MCMMetadataIdentifier"] as? String {
                if id.lowercased().contains(keyword) {
                    return dir
                }
            }
        }
        return nil
    }
}