import Foundation
import UIKit

// MARK: - ContainerStore
enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"
    static let systemDataRoot = "/var/mobile/Containers/Data/System"
    static let sharedDataRoot = "/var/mobile/Containers/Shared/AppGroup"
    
    static func resolveAppContainerPath(bundleID: String) -> String? {
        // Sử dụng API của LSApplicationWorkspace (chuẩn của 3105)
        if let path = LSApplicationWorkspace.default().applicationProxy(forBundleIdentifier: bundleID)?.dataContainerURL?.path {
            return path
        }
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
    
    // MARK: - Granting Access (Tích hợp lõi 3106)
    static func grantContainerAccess(_ path: String) -> Int64 {
        return SandboxAccess.grant(path: path)
    }
    
    static func releaseContainerAccess(_ handle: Int64) {
        SandboxAccess.release(handle)
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
}