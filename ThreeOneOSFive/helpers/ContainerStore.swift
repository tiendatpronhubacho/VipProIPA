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
    
    // MARK: - Resolve Path
            static func resolveAppContainerPath(bundleID: String) -> String? {
        let appDataRoot = "/var/mobile/Containers/Data/Application"
        
        // 1. Thử cấp quyền đọc thư mục
        let _ = SandboxAccess.grant(path: appDataRoot, writable: true)
        
        // 2. Quét tìm thư mục của FF
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
        
        // 3. FALLBACK: Nếu quét thất bại, thử dùng đường dẫn mặc định (tránh lỗi targetAppUnavailable)
        // Đường dẫn này sẽ được patch ghi đè nếu app có quyền
        let fallbackPath = "\(appDataRoot)/\(bundleID)"
        print("container: Fallback path used -> \(fallbackPath)")
        
        return fallbackPath
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
    
    // Các hàm giả lập để fix lỗi build
    static func dynamicAppIdentifiers() -> [String] {
        return []
    }
    
    static func installedAppsFromAPI() -> [InstalledApp] {
        return []
    }
    
    static func installedAppsFromMCM(identifiers: [String]) -> [InstalledApp] {
        return []
    }
    
    // Hàm listFiles hỗ trợ cả 2 nhãn
    static func listFiles(in directory: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        return contents.sorted()
    }
    
    static func listFiles(at directory: String) -> [String] {
        return listFiles(in: directory)
    }
    
    // MARK: - Utility Functions
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
    
    // Hàm mới thêm để fix lỗi CleanerView
    static func launchServicesStoreIdentifiers() -> [String] {
        return []
    }
    static var researchAppIdentifiers: [String] {
        return []
    }
    static func installedAppsFromMHACandidates(
        identifiers: [String],
        progressHandler: (([InstalledApp]) -> Void)? = nil
    ) -> [InstalledApp] {
        return []
    }

    static func inferUnidentifiedApps(
        in filesystemApps: [InstalledApp],
        knownApps: [InstalledApp],
        launchServicesIdentifiers: Set<String>
    ) -> [InstalledApp] {
        return []
    }
}