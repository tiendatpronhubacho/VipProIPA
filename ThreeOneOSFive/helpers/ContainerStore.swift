import Foundation
import Darwin
import UIKit

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let containerPath: String
    let version: String
    let icon: UIImage?
    var id: String { bundleID }
    var displayName: String { AppDisplayNamePolicy.resolve(bundleID: bundleID, candidates: [name]) }
    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct FileEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    var id: String { path }
    var sizeText: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"
    static let systemDataRoot = "/var/mobile/Containers/Data/System"
    
    private static var shouldUseBadQuery: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }
    
    static func resolveAppContainerPath(bundleID: String) -> String? {
        // 1. Ưu tiên quét file plist trực tiếp (Lách iOS 26, load cực nhanh)
        let dirs = enumerateDirectories(path: appDataRoot)
        for dir in dirs {
            let metadataPath = (dir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let id = plist["MCMMetadataIdentifier"] as? String {
                
                let lowerID = id.lowercased()
                let targetID = bundleID.lowercased()
                
                if lowerID == targetID || 
                   (targetID.contains("garena") && (lowerID.contains("garena") || lowerID.contains("ffvn"))) {
                    return dir
                }
            }
        }
        
        // 2. Fallback MCM (chỉ chạy nếu cách 1 thất bại)
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            return path
        }
        
        return nil
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        return path.contains("/var/mobile/Containers/Data/Application/")
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

    static func grantContainerAccess(_ containerPath: String) -> Int64 {
        guard shouldUseBadQuery else { return -1 }
        let clean = containerPath.hasSuffix("/") ? String(containerPath.dropLast()) : containerPath
        var pathC = clean.utf8CString.map { Int8($0) }
        return bad_query(&pathC, true, nil, false)
    }
    
    // --- CÁC HÀM GIẢ LẬP ĐỂ VIEW KHÔNG BÁO LỖI ---
    static func installedAppsFromAPI() -> [InstalledApp] { return [] }
    static func containersFromFilesystem() -> [InstalledApp] { return [] }
    static func listFiles(at path: String) -> [FileEntry] { return [] }
    static func readTextFile(at path: String, limit: Int = 200_000) -> String { return "" }
    static func readContainerMetadata(containerPath: String) -> ContainerMetadata? { return nil }
    static func metadataPath(for containerPath: String) -> String { return "" }
    static func applicationBundleMetadataCatalog() -> [String: ApplicationBundleMetadata] { return [:] }
    static func applyingBundleMetadata(to apps: [InstalledApp], catalog: [String: ApplicationBundleMetadata]) -> [InstalledApp] { return apps }
    static func dynamicAppIdentifiers() -> [String] { return [] }
    static func installedAppsFromMCM(identifiers: [String]? = nil, bundleMetadata: [String: ApplicationBundleMetadata] = [:]) -> [InstalledApp] { return [] }
    static func installedAppsFromMHACandidates(identifiers: [String], bundleMetadata: [String: ApplicationBundleMetadata] = [:], progress: (([InstalledApp]) -> Void)? = nil) -> [InstalledApp] { return [] }
    static func launchServicesStoreIdentifiers() -> [String] { return [] }
    static func enumerateDirectoriesWithTraversalGrant(path: String) -> [String] { return enumerateDirectories(path: path) }
    static func inferredApp(for fallback: InstalledApp, knownAppsByBundleID: [String: InstalledApp], launchServicesIdentifiers: Set<String>) -> InstalledApp? { return fallback }
    static func inferUnidentifiedApps(in apps: [InstalledApp], knownApps: [InstalledApp], launchServicesIdentifiers: Set<String> = []) -> [InstalledApp] { return apps }
}