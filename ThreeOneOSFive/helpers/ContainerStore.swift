import Foundation
import UIKit

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let version: String
    let containerPath: String
    
    var displayName: String { name }
}

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"
    static let systemDataRoot = "/var/mobile/Containers/Data/System"
    static let sharedDataRoot = "/var/mobile/Containers/Shared/AppGroup"
    
    // MARK: - Resolve Path (Đồng bộ 3105 và 3106)
    static func resolveAppContainerPath(bundleID: String) -> String? {
        // 1. Thử MCMActivateContainerPath của 3105 (hoạt động tốt trên bad_query và kernel)
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            log("patch: MCM resolved \(bundleID)")
            return path
        }
        
        // 2. Fallback: Quét thư mục (dùng cho worse_query hoặc nếu MCM bị từ chối)
        if let scanned = resolveAppContainerPathByMetadataScan(bundleID: bundleID) {
            log("patch: Metadata scan resolved \(bundleID)")
            return scanned
        }
        
        // 3. Fallback cuối cùng: Dùng SandboxAccess grant thư mục cha rồi đọc metadata
        let handle = SandboxAccess.grant(path: appDataRoot, writable: false)
        if handle >= 0 {
            defer { SandboxAccess.release(handle) }
            let fm = FileManager.default
            if let uuids = try? fm.contentsOfDirectory(atPath: appDataRoot) {
                for uuid in uuids {
                    let metaPath = "\(appDataRoot)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let id = plist["MCMMetadataIdentifier"] as? String,
                       id == bundleID {
                        return "\(appDataRoot)/\(uuid)"
                    }
                }
            }
        }
        
        return nil
    }
    
    static func resolveAppContainerPathByMetadataScan(bundleID: String) -> String? {
        let dirs = enumerateDirectories(path: appDataRoot)
        guard !dirs.isEmpty else { return nil }
        for dir in dirs {
            guard UUID(uuidString: (dir as NSString).lastPathComponent) != nil else { continue }
            let metaPath = "\(dir)/.com.apple.mobile_container_manager.metadata.plist"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let id = plist["MCMMetadataIdentifier"] as? String,
               id == bundleID {
                return dir
            }
        }
        return nil
    }
    
    static func enumerateDirectories(path: String, maxInode: Int64 = 2_000_000) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
            return names.map { (clean as NSString).appendingPathComponent($0) }
        }
        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, maxInode) else { return [] }
        defer { free(result) }
        return String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    static func isApplicationContainerPath(_ path: String) -> Bool {
        let cleanPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        return cleanPath.hasPrefix(appDataRoot + "/") || cleanPath.hasPrefix("/private" + appDataRoot + "/")
    }
    
    static func isSystemContainerPath(_ path: String) -> Bool {
        let cleanPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        return cleanPath.hasPrefix(systemDataRoot + "/") || cleanPath.hasPrefix("/private" + systemDataRoot + "/")
    }
    
    static func isSharedContainerPath(_ path: String) -> Bool {
        let cleanPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        return cleanPath.hasPrefix(sharedDataRoot + "/") || cleanPath.hasPrefix("/private" + sharedDataRoot + "/")
    }
    
    // MARK: - Granting Access
    static func grantContainerAccess(_ path: String) -> Int64 {
        return SandboxAccess.grant(path: path)
    }
    
    static func releaseContainerAccess(_ handle: Int64) {
        SandboxAccess.release(handle)
    }
    
    static func ensureWriteAccess(to bundleID: String) -> URL? {
        guard let path = resolveAppContainerPath(bundleID: bundleID) else { return nil }
        let grant = grantContainerAccess(path)
        if grant >= 0 {
            releaseContainerAccess(grant)
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }
    
    static func dynamicAppIdentifiers() -> [String] {
        let identifiers = MCMEnumerateIdentifiersForClass(2, 1024, nil)
        return identifiers
    }
    
    static func installedAppsFromAPI() -> [InstalledApp] {
        let raw = installedAppInfo() as? [String: [String: Any]] ?? [:]
        var apps: [InstalledApp] = []
        for (bundleID, info) in raw {
            var containerPath = info["container"] as? String ?? ""
            if containerPath.isEmpty {
                var lookupError: NSString?
                if let resolved = MCMActivateContainerPath(2, bundleID, false, &lookupError),
                   isApplicationContainerPath(resolved) {
                    containerPath = resolved
                }
            }
            guard !containerPath.isEmpty else { continue }
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: info["name"] as? String ?? "",
                version: info["version"] as? String ?? "",
                containerPath: containerPath
            ))
        }
        return apps
    }
    
    static func installedAppsFromMCM(identifiers: [String]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for bundleID in identifiers {
            var lookupError: NSString?
            guard let containerPath = MCMActivateContainerPath(2, bundleID, false, &lookupError) else { continue }
            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: rawInfo["name"] as? String ?? bundleID,
                version: rawInfo["version"] as? String ?? "",
                containerPath: containerPath
            ))
        }
        return apps
    }
    
    static func listFiles(at path: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return contents.sorted()
    }
    
    static func listFiles(in directory: String) -> [String] {
        return listFiles(at: directory)
    }
    
    static func containerType(for path: String) -> String {
        if isApplicationContainerPath(path) { return "Application" }
        if isSystemContainerPath(path) { return "System" }
        if isSharedContainerPath(path) { return "App Group" }
        return "Unknown"
    }
    // MARK: - Hàm giả lập để fix lỗi CleanerView và AppDataBrowserView
    static func launchServicesStoreIdentifiers() -> [String] {
        return []
    }
}