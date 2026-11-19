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
    private static var shouldUseBadQuery: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 }
    
    static let researchAppIdentifiers = [
        "com.apple.mobilesafari", "com.apple.mobilenotes", "com.apple.Maps", "com.apple.facetime",
        "com.apple.iBooks", "com.apple.podcasts", "com.apple.PosterBoard", "com.apple.mobilemail",
        "com.apple.weather", "com.apple.camera", "com.apple.Health", "com.apple.Fitness",
        "com.apple.tips", "com.apple.Passbook", "com.apple.reminders", "com.apple.stocks",
        "com.apple.news", "com.apple.Home", "com.apple.tv", "com.apple.shortcuts",
        "com.apple.freeform", "com.apple.calculator", "com.apple.MobileSMS", "com.apple.InCallService",
        "com.apple.Preferences", "com.apple.springboard", "com.apple.Photos", "com.apple.AppStore",
        "com.apple.Music", "com.apple.Bridge", "com.apple.Clock", "com.apple.VoiceMemos",
        "com.apple.Translate", "com.apple.measure", "com.apple.compass", "com.apple.Magnifier", "com.apple.DocumentsApp"
    ]

    // SỬ DỤNG DIRECT CONTAINER QUERY CỦA 3106
    static func resolveAppContainerPath(bundleID: String) -> String? {
        // Gọi trực tiếp hàm xin quyền của 3106
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError) {
            if isApplicationContainerPath(path) { return path }
        }
        
        // Fallback cho Free Fire nếu MCM bị chặn
        if bundleID.contains("garena") || bundleID.contains("ffvn") {
            let dirs = enumerateDirectories(path: appDataRoot)
            for dir in dirs {
                let metaPath = (dir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let id = plist["MCMMetadataIdentifier"] as? String,
                   id.contains("garena") || id.contains("ffvn") {
                    return dir
                }
            }
        }
        return nil
    }
    
    static func resolveAppContainerPathByDirectoryScan(bundleID: String) -> String? { return resolveAppContainerPath(bundleID: bundleID) }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        let canonicalRoot = ContainerDiscoveryMerger.canonicalPath(appDataRoot)
        let canonicalPath = ContainerDiscoveryMerger.canonicalPath(path)
        return canonicalPath.hasPrefix(canonicalRoot + "/") && UUID(uuidString: (canonicalPath as NSString).lastPathComponent) != nil
    }

    static func enumerateDirectories(path: String, maxInode: Int64 = 2_000_000) -> [String] {
        if let names = try? FileManager.default.contentsOfDirectory(atPath: path), !names.isEmpty { return names.map { (path as NSString).appendingPathComponent($0) } }
        var pathC = path.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, maxInode) else { return [] }
        defer { free(result) }
        return String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // SỬ DỤNG HÀM GRANT CỦA 3106
    static func grantContainerAccess(_ containerPath: String) -> Int64 {
        guard shouldUseBadQuery else { return -1 }
        var pathC = containerPath.utf8CString.map { Int8($0) }
        return bad_query(&pathC, true, nil, false)
    }

    // MARK: - HÀM MỚI: Ensure Write Access
    static func ensureWriteAccess(to bundleID: String) -> URL? {
        guard let path = resolveAppContainerPath(bundleID: bundleID) else { return nil }
        _ = grantContainerAccess(path)
        return URL(fileURLWithPath: path)
    }

    // Các hàm giả lập để View không lỗi
    static func installedAppsFromAPI() -> [InstalledApp] { return [] }
    static func applicationBundleMetadataCatalog() -> [String: ApplicationBundleMetadata] { return [:] }
    static func applyingBundleMetadata(to apps: [InstalledApp], catalog: [String: ApplicationBundleMetadata]) -> [InstalledApp] { return apps }
    static func dynamicAppIdentifiers() -> [String] { return [] }
    static func installedAppsFromMCM(identifiers: [String]? = nil, bundleMetadata: [String: ApplicationBundleMetadata] = [:]) -> [InstalledApp] { return [] }
    static func installedAppsFromMHACandidates(identifiers: [String], bundleMetadata: [String: ApplicationBundleMetadata] = [:], progress: (([InstalledApp]) -> Void)? = nil) -> [InstalledApp] { return [] }
    static func launchServicesStoreIdentifiers() -> [String] { return [] }
    static func enumerateDirectoriesWithTraversalGrant(path: String) -> [String] { return enumerateDirectories(path: path) }
    static func readContainerMetadata(containerPath: String) -> ContainerMetadata? { return nil }
    static func metadataPath(for containerPath: String) -> String { return "" }
    static func containersFromFilesystem() -> [InstalledApp] { return [] }
    static func inferredApp(for fallback: InstalledApp, knownAppsByBundleID: [String: InstalledApp], launchServicesIdentifiers: Set<String>) -> InstalledApp? { return fallback }
    static func inferUnidentifiedApps(in apps: [InstalledApp], knownApps: [InstalledApp], launchServicesIdentifiers: Set<String> = []) -> [InstalledApp] { return apps }
    static func listFiles(at path: String) -> [FileEntry] { return [] }
    static func readTextFile(at path: String, limit: Int = 200_000) -> String { return "" }
}