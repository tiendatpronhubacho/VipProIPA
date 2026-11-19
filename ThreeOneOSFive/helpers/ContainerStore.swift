import Foundation
import Darwin
import UIKit

// ... (Giữ nguyên struct InstalledApp và FileEntry như cũ)
struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let containerPath: String
    let version: String
    let icon: UIImage?
    var id: String { bundleID }
    var displayName: String {
        AppDisplayNamePolicy.resolve(bundleID: bundleID, candidates: [name])
    }
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
        // Tối ưu: Trên iOS 26, dùng bad_query trực tiếp để lấy quyền truy cập
        if shouldUseBadQuery {
            let cleanID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            var idC = cleanID.utf8CString.map { Int8($0) }
            // Thử dùng bad_query với App Group (is_group = true)
            let handle = bad_query(&idC, true, nil, true)
            if handle >= 0 {
                // Lấy path từ handle (nếu bad_query hỗ trợ trả về path, nhưng thường nó chỉ grant)
                // Ta cần tự dựng path từ bundle ID
                let path = "/var/mobile/Containers/Data/Application/\(cleanID)"
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
                bad_query_release(handle)
            }
        }
        
        // Fallback 1: Dùng MCM (cách cũ)
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            return path
        }
        
        // Fallback 2: Quét file plist (chỉ chạy khi bad_query/MCM thất bại)
        if let bruteForced = resolveAppContainerPathByDirectoryScan(bundleID: bundleID) {
            return bruteForced
        }
        
        return nil
    }
    
    // Hàm quét file plist (giữ nguyên)
    static func resolveAppContainerPathByDirectoryScan(bundleID: String) -> String? {
        let dirs = enumerateDirectories(path: appDataRoot)
        for dir in dirs {
            let metadataPath = (dir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let id = plist["MCMMetadataIdentifier"] as? String,
               id == bundleID {
                let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
                if isApplicationContainerPath(canonical) {
                    return canonical
                }
            }
        }
        return nil
    }

    // ... (Giữ nguyên các hàm installedAppsFromAPI, applyingBundleMetadata, v.v...)
    // Bạn có thể copy lại các hàm cũ từ file trước, chỉ cần thay thế 2 hàm resolve ở trên là được.
}