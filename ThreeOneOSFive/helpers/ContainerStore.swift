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
        
        // 1. Lấy thông tin phiên bản iOS
        let v = ProcessInfo.processInfo.operatingSystemVersion
        
        // 2. KIỂM TRA IOS 17/18 (Dùng Kernel Exploit)
        if v.majorVersion < 26 {
            log("container: iOS \(v.majorVersion) - Dùng kernel exploit...")
            
            // Thử đọc trực tiếp (nếu đã có root)
            if let uuids = try? FileManager.default.contentsOfDirectory(atPath: appDataRoot) {
                for uuid in uuids {
                    let metaPath = "\(appDataRoot)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let id = plist["MCMMetadataIdentifier"] as? String,
                       id == bundleID {
                        return "\(appDataRoot)/\(uuid)"
                    }
                }
            } else {
                // Nếu không đọc được, dùng sandbox_escape (nếu có)
                log("container: Không đọc được thư mục. Thử escape bằng kernel...")
                let selfProc = proc_self()
                if selfProc != 0 {
                    _ = sandbox_escape(selfProc)
                }
                
                // Thử đọc lại sau khi escape
                if let uuids = try? FileManager.default.contentsOfDirectory(atPath: appDataRoot) {
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
        
        // 3. KIỂM TRA IOS 26/27 (Dùng Sandbox Escape WQFiles)
        log("container: iOS \(v.majorVersion) - Dùng Sandbox Escape...")
        
        // Ép cấp quyền bằng MCM (MobileContainerManager)
        var activationError: NSString?
        let mcmHandle = MCMActivateContainer(2, bundleID, false, &activationError)
        if mcmHandle >= 0 {
            SandboxAccess.release(mcmHandle)
        }
        
        // Ép cấp quyền bằng WQFiles
        let grantHandle = SandboxAccess.grant(path: appDataRoot, writable: true)
        if grantHandle >= 0 {
            SandboxAccess.release(grantHandle)
        }
        
        // Quét thư mục
        let fm = FileManager.default
        guard let uuids = try? fm.contentsOfDirectory(atPath: appDataRoot) else {
            let err = "Không thể đọc thư mục Application! (Sandbox chưa escape hoặc chứng chỉ không có App Group)."
            UserDefaults.standard.set(err, forKey: "debug_bootstrap_error")
            log("container: \(err)")
            return nil
        }
        
        for uuid in uuids {
            let metaPath = "\(appDataRoot)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let id = plist["MCMMetadataIdentifier"] as? String,
               id == bundleID {
                log("container: Tìm thấy \(bundleID) tại \(uuid)")
                return "\(appDataRoot)/\(uuid)"
            }
        }
        
        let err = "Không tìm thấy \(bundleID) trong \(uuids.count) thư mục. (Có thể Free Fire chưa cài hoặc sai Bundle ID)"
        UserDefaults.standard.set(err, forKey: "debug_bootstrap_error")
        log("container: \(err)")
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