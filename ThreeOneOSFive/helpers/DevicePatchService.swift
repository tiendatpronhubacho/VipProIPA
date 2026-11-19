import Foundation

enum DevicePatchService {
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
                    // Nếu không tìm thấy, thử dùng root đầu tiên (cho trường hợp quét mò)
                    if let firstRoot = roots.values.first { return firstRoot }
                    throw PatchPackageError.targetAppUnavailable(bundleID)
                },
                backupCenter: .shared
            )
        }
    }

    // ... (Các hàm inspectRestore, restore, resetToAppliedState giữ nguyên)

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    // Hàm tự động sửa Bundle ID
    private static func fixBundleID(_ bundleID: String) -> String {
        let lower = bundleID.lowercased()
        if lower.contains("ffvn") || lower.contains("freefire") || lower.contains("garena") {
            // Trả về bundle ID chuẩn (dù máy có thể không tìm thấy)
            return "com.garena.ffvn"
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
            var path = ContainerStore.resolveAppContainerPath(bundleID: bundleID)
            
            // Nếu không tìm thấy, thử quét trực tiếp trên ổ cứng để tìm thư mục chứa chữ "garena" hoặc "ffvn"
            if path == nil && bundleID.contains("garena") {
                if let foundPath = findGameFolderByKeyword(keyword: "garena") {
                    path = foundPath
                } else if let foundPath = findGameFolderByKeyword(keyword: "ffvn") {
                    path = foundPath
                }
            }

            guard let validPath = path, ContainerStore.isApplicationContainerPath(validPath) else {
                // Nếu vẫn không được, dùng đại thư mục Data/Application (fallback rủi ro)
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
    
    // Hàm phụ: Quét thư mục bằng keyword
    private static func findGameFolderByKeyword(keyword: String) -> String? {
        // Thử liệt kê thư mục data/application
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