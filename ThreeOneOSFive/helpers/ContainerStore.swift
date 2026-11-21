import Foundation
import UIKit
import NetworkExtension

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
    
    // MARK: - Resolve Path
    static func resolveAppContainerPath(bundleID: String) -> String? {
        // 1. Xin quyền đọc thư mục Application
        let handle = SandboxAccess.grant(path: appDataRoot, writable: false)
        guard handle >= 0 else {
            UserDefaults.standard.set("Lỗi: Không xin được quyền đọc Application", forKey: "debug_bootstrap_error")
            return nil
        }
        
        // Không release handle ở đây, để nó mở cho các thao tác sau
        // (Handle này sẽ được DevicePatchService quản lý và release sau)
        
        let fm = FileManager.default
        guard let uuids = try? fm.contentsOfDirectory(atPath: appDataRoot) else {
            UserDefaults.standard.set("Lỗi: Không đọc được thư mục Application (Quyền bị từ chối)!", forKey: "debug_bootstrap_error")
            return nil
        }
        
        for uuid in uuids {
            let metaPath = "\(appDataRoot)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let id = plist["MCMMetadataIdentifier"] as? String,
               id == bundleID {
                return "\(appDataRoot)/\(uuid)"
            }
        }
        
        UserDefaults.standard.set("Lỗi: Không tìm thấy \(bundleID)", forKey: "debug_bootstrap_error")
        return nil
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
    
    // Các hàm giả lập
    static func dynamicAppIdentifiers() -> [String] { return [] }
    static func installedAppsFromAPI() -> [InstalledApp] { return [] }
    static func installedAppsFromMCM(identifiers: [String]) -> [InstalledApp] { return [] }
    
    static func listFiles(in directory: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return contents.sorted()
    }
    
    static func listFiles(at directory: String) -> [String] {
        return listFiles(in: directory)
    }
    
    static func containerIdentity(for path: String) -> String? {
        let components = path.components(separatedBy: "/")
        guard let last = components.last, !last.isEmpty else { return nil }
        return last
    }
    
    static func isRootPath(_ path: String) -> Bool {
        return path == appDataRoot || path == "/private" + appDataRoot ||
               path == systemDataRoot || path == "/private" + systemDataRoot ||
               path == sharedDataRoot || path == "/private" + sharedDataRoot
    }
    
    static func parentPath(of path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        return parent.isEmpty ? nil : parent
    }
    
    static func appDataRoots() -> [String] {
        return [appDataRoot, "/private" + appDataRoot]
    }
    
    static func containerType(for path: String) -> String {
        if isApplicationContainerPath(path) { return "Application" }
        if isSystemContainerPath(path) { return "System" }
        if isSharedContainerPath(path) { return "App Group" }
        return "Unknown"
    }
    
    static func launchServicesStoreIdentifiers() -> [String] { return [] }
    static var researchAppIdentifiers: [String] { return [] }
    static func installedAppsFromMHACandidates(identifiers: [String], progressHandler: (([InstalledApp]) -> Void)? = nil) -> [InstalledApp] { return [] }
    static func inferUnidentifiedApps(in filesystemApps: [InstalledApp], knownApps: [InstalledApp], launchServicesIdentifiers: Set<String>) -> [InstalledApp] { return [] }
}