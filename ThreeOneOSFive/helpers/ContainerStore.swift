import Foundation
import Darwin
import UIKit

// MARK: - Models

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let version: String       // Sửa lại thứ tự: version trước
    let containerPath: String // containerPath sau
    var icon: UIImage? = nil

    var id: String { bundleID }
    var displayName: String {
        AppDisplayNamePolicy.resolve(bundleID: bundleID, candidates: [name])
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Store

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"
    static let systemDataRoot = "/var/mobile/Containers/Data/System"
    private static var shouldUseBadQuery: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }
    private static let applicationBundleRoots: [(path: String, nested: Bool)] = [
        ("/var/containers/Bundle/Application", true),
        ("/Applications", false),
        ("/System/Applications", false)
    ]
    static let researchAppIdentifiers = [
        "com.apple.mobilesafari", "com.apple.mobilenotes", "com.apple.Maps",
        "com.apple.facetime", "com.apple.iBooks", "com.apple.podcasts",
        "com.apple.PosterBoard", "com.apple.mobilemail", "com.apple.weather",
        "com.apple.camera", "com.apple.Health", "com.apple.Fitness",
        "com.apple.tips", "com.apple.Passbook", "com.apple.reminders",
        "com.apple.stocks", "com.apple.news", "com.apple.Home", "com.apple.tv",
        "com.apple.shortcuts", "com.apple.freeform", "com.apple.calculator",
        "com.apple.MobileSMS", "com.apple.InCallService", "com.apple.Preferences",
        "com.apple.springboard", "com.apple.Photos", "com.apple.AppStore",
        "com.apple.Music", "com.apple.Bridge", "com.apple.Clock",
        "com.apple.VoiceMemos", "com.apple.Translate", "com.apple.measure",
        "com.apple.compass", "com.apple.Magnifier", "com.apple.DocumentsApp"
    ]

    static func resolveAppContainerPath(bundleID: String) -> String? {
        guard (try? PatchPathValidator.canonicalBundleIdentifier(bundleID)) == bundleID else {
            return nil
        }
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            return path
        }
        if let scanned = resolveAppContainerPathByMetadataScan(bundleID: bundleID) {
            return scanned
        }
        return nil
    }

    static func resolveAppContainerPathByMetadataScan(bundleID: String) -> String? {
        if KernelExploit.requiresSandboxEscape, !KernelExploit.hasSandboxAccess() {
            return nil
        }
        let dirs = enumerateDirectories(path: appDataRoot)
        guard !dirs.isEmpty else { return nil }
        for dir in dirs {
            guard UUID(uuidString: (dir as NSString).lastPathComponent) != nil else { continue }
            guard let metadata = readContainerMetadata(containerPath: dir),
                  metadata.bundleID == bundleID else { continue }
            let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
            guard isApplicationContainerPath(canonical) else { continue }
            return canonical
        }
        return nil
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
                containerPath: containerPath,
                icon: info["icon"] as? UIImage
            ))
        }
        return apps
    }

    static func applicationBundleMetadataCatalog() -> [String: ApplicationBundleMetadata] {
        var catalog: [String: ApplicationBundleMetadata] = [:]
        for root in applicationBundleRoots {
            for metadata in applicationBundleMetadata(at: root.path, nested: root.nested) {
                catalog[metadata.bundleID] = metadata
            }
        }
        return catalog
    }

    static func applyingBundleMetadata(
        to apps: [InstalledApp],
        catalog: [String: ApplicationBundleMetadata]
    ) -> [InstalledApp] {
        apps.map { app in
            guard let metadata = catalog[app.bundleID] else { return app }
            return InstalledApp(
                bundleID: app.bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: app.bundleID,
                    candidates: [metadata.displayName, app.name]
                ),
                version: app.version.isEmpty ? metadata.version : app.version,
                containerPath: app.containerPath,
                icon: app.icon
            )
        }
    }

    static func dynamicAppIdentifiers() -> [String] {
        let identifiers = MCMEnumerateIdentifiersForClass(2, 1024, nil)
        return identifiers
    }

    static func installedAppsFromMCM(
        identifiers: [String]? = nil,
        bundleMetadata: [String: ApplicationBundleMetadata] = [:]
    ) -> [InstalledApp] {
        let identifiers = identifiers ?? dynamicAppIdentifiers()
        var apps: [InstalledApp] = []
        for bundleID in identifiers {
            var lookupError: NSString?
            guard let containerPath = MCMActivateContainerPath(2, bundleID, false, &lookupError) else { continue }
            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            let metadata = bundleMetadata[bundleID]
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: bundleID,
                    candidates: [metadata?.displayName, rawInfo["name"] as? String]
                ),
                version: rawInfo["version"] as? String ?? metadata?.version ?? "",
                containerPath: containerPath,
                icon: rawInfo["icon"] as? UIImage
            ))
        }
        return apps
    }

    static func installedAppsFromMHACandidates(
        identifiers: [String],
        bundleMetadata: [String: ApplicationBundleMetadata] = [:],
        progress: (([InstalledApp]) -> Void)? = nil
    ) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for bundleID in identifiers {
            var lookupError: NSString?
            guard let containerPath = MCMActivateContainerPath(2, bundleID, false, &lookupError),
                  isApplicationContainerPath(containerPath) else { continue }
            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            let metadata = bundleMetadata[bundleID]
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: bundleID,
                    candidates: [metadata?.displayName, rawInfo["name"] as? String]
                ),
                version: rawInfo["version"] as? String ?? metadata?.version ?? "",
                containerPath: containerPath,
                icon: rawInfo["icon"] as? UIImage
            ))
            if apps.count.isMultiple(of: 8) { progress?(apps) }
        }
        progress?(apps)
        return apps
    }

    private static func applicationBundleMetadata(
        at rootPath: String,
        nested: Bool
    ) -> [ApplicationBundleMetadata] {
        let handle = grantContainerAccess(rootPath)
        defer { if handle >= 0 { releaseContainerAccess(handle) } }
        let fileManager = FileManager.default
        guard let rootEntries = try? fileManager.contentsOfDirectory(atPath: rootPath) else { return [] }
        let bundlePaths: [String]
        if nested {
            bundlePaths = rootEntries.prefix(2_048).flatMap { entry -> [String] in
                guard UUID(uuidString: entry) != nil else { return [] }
                let containerPath = (rootPath as NSString).appendingPathComponent(entry)
                let children = (try? fileManager.contentsOfDirectory(atPath: containerPath)) ?? []
                return children.prefix(16).compactMap { child in
                    guard child.hasSuffix(".app") else { return nil }
                    return (containerPath as NSString).appendingPathComponent(child)
                }
            }
        } else {
            bundlePaths = rootEntries.prefix(2_048).compactMap { entry in
                guard entry.hasSuffix(".app") else { return nil }
                return (rootPath as NSString).appendingPathComponent(entry)
            }
        }
        return bundlePaths.compactMap { bundlePath in
            let infoPath = (bundlePath as NSString).appendingPathComponent("Info.plist")
            let infoSize = (try? fileManager.attributesOfItem(atPath: infoPath)[.size] as? NSNumber)?.int64Value ?? 0
            guard infoSize > 0, infoSize <= 2 * 1024 * 1024 else { return nil }
            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPath)) else { return nil }
            return ApplicationBundleMetadataReader.metadata(
                from: plistData,
                localizedInfo: Bundle(path: bundlePath)?.localizedInfoDictionary
            )
        }
    }

    static func launchServicesStoreIdentifiers() -> [String] {
        var cachePaths: [String] = []
        var seenCachePaths = Set<String>()
        func addCachePath(_ rawPath: String) {
            let path = ContainerDiscoveryMerger.canonicalPath(rawPath)
            guard !path.isEmpty, seenCachePaths.insert(path).inserted else { return }
            cachePaths.append(path)
        }
        var leasedCachePaths = Set<String>()
        var serviceLookupError: NSString?
        if let servicePath = MCMActivateContainerPath(10, "com.apple.lsd", false, &serviceLookupError) {
            let cachePath = (servicePath as NSString).appendingPathComponent("Library/Caches")
            addCachePath(cachePath)
            leasedCachePaths.insert(ContainerDiscoveryMerger.canonicalPath(cachePath))
        } else if shouldUseBadQuery {
            let detail = serviceLookupError.map { String($0) } ?? "no path"
            log("browser: MCM com.apple.lsd activation unavailable detail=\(detail)")
        }
        let traversedSystemDirectories = enumerateDirectoriesWithTraversalGrant(path: systemDataRoot)
        let systemDirectories = traversedSystemDirectories.isEmpty ? enumerateDirectories(path: systemDataRoot) : traversedSystemDirectories
        for directory in systemDirectories {
            guard readContainerMetadata(containerPath: directory)?.bundleID == "com.apple.lsd" else { continue }
            addCachePath((directory as NSString).appendingPathComponent("Library/Caches"))
        }
        addCachePath("/var/db/lsd")
        addCachePath("/var/mobile/Library/Caches")
        var identifiers: [String] = []
        var seenIdentifiers = Set<String>()
        let maximumCandidateCount = 65536
        for cachePath in cachePaths where identifiers.count < maximumCandidateCount {
            let hasLease = leasedCachePaths.contains(ContainerDiscoveryMerger.canonicalPath(cachePath))
            let handle: Int64 = hasLease || !shouldUseBadQuery ? -1 : grantContainerAccess(cachePath)
            if handle < 0 && !hasLease && shouldUseBadQuery { continue }
            defer { if handle >= 0 { releaseContainerAccess(handle) } }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: cachePath)) ?? []
            for name in names where identifiers.count < maximumCandidateCount {
                guard name.hasPrefix("com.apple.LaunchServices-"), name.hasSuffix("-v2.csstore") else { continue }
                let storePath = (cachePath as NSString).appendingPathComponent(name)
                guard let size = (try? FileManager.default.attributesOfItem(atPath: storePath)[.size]) as? NSNumber,
                      size.uint64Value > 0, size.uint64Value <= 64 * 1024 * 1024,
                      let data = try? Data(contentsOf: URL(fileURLWithPath: storePath), options: .mappedIfSafe) else { continue }
                let remaining = maximumCandidateCount - identifiers.count
                let extracted = LaunchServicesCandidateExtractor.identifiers(from: data, limit: remaining)
                for identifier in extracted where seenIdentifiers.insert(identifier).inserted {
                    identifiers.append(identifier)
                }
            }
        }
        return identifiers
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        let canonicalRoot = ContainerDiscoveryMerger.canonicalPath(appDataRoot)
        let canonicalPath = ContainerDiscoveryMerger.canonicalPath(path)
        guard canonicalPath.hasPrefix(canonicalRoot + "/") else { return false }
        return UUID(uuidString: (canonicalPath as NSString).lastPathComponent) != nil
    }

    static func enumerateDirectories(path: String, maxInode: Int64 = 2_000_000) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard clean.hasPrefix("/") else { return [] }
        if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
            return names.map { (clean as NSString).appendingPathComponent($0) }
        }
        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, maxInode) else { return [] }
        defer { free(result) }
        return String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    static func enumerateDirectoriesWithTraversalGrant(path: String) -> [String] {
        if !shouldUseBadQuery {
            if let names = try? FileManager.default.contentsOfDirectory(atPath: path), !names.isEmpty {
                return names.map { (path as NSString).appendingPathComponent($0) }
            }
            return enumerateDirectories(path: path)
        }
        let handle = grantContainerAccess(path)
        if handle >= 0 {
            defer { releaseContainerAccess(handle) }
            if let names = try? FileManager.default.contentsOfDirectory(atPath: path), !names.isEmpty {
                return names.map { (path as NSString).appendingPathComponent($0) }
            }
        }
        return enumerateDirectories(path: path)
    }

    static func readContainerMetadata(containerPath: String) -> ContainerMetadata? {
        let metadataPath = metadataPath(for: containerPath)
        var data: Data?
        if let fd = fopen(metadataPath, "r") {
            var buffer = [UInt8](repeating: 0, count: 65536)
            var bytes: [UInt8] = []
            while true {
                let n = fread(&buffer, 1, buffer.count, fd)
                if n <= 0 { break }
                bytes.append(contentsOf: buffer[0..<n])
            }
            fclose(fd)
            if !bytes.isEmpty { data = Data(bytes) }
        }
        if data == nil { data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)) }
        guard let validData = data,
              let plist = try? PropertyListSerialization.propertyList(from: validData, options: [], format: nil) as? [String: Any] else { return nil }
        let bundleID = plist["MCMMetadataIdentifier"] as? String ?? ""
        var displayName = ""
        if let info = plist["MCMMetadataInfo"] as? [String: Any] {
            displayName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ""
        }
        return ContainerMetadata(bundleID: bundleID, displayName: displayName)
    }

    static func metadataPath(for containerPath: String) -> String {
        (containerPath as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
    }

    static func grantContainerAccess(_ containerPath: String) -> Int64 {
        return SandboxAccess.grant(path: containerPath)
    }

    static func releaseContainerAccess(_ handle: Int64) {
        SandboxAccess.release(handle)
    }

    static func containersFromFilesystem() -> [InstalledApp] {
        let grantedDirectories = enumerateDirectoriesWithTraversalGrant(path: appDataRoot)
        let dirs = grantedDirectories.isEmpty ? enumerateDirectories(path: appDataRoot) : grantedDirectories
        return dirs.compactMap { dir -> InstalledApp? in
            let uuid = (dir as NSString).lastPathComponent
            guard UUID(uuidString: uuid) != nil else { return nil }
            let fallback = ContainerIdentityResolver.fallbackIdentity(containerPath: dir)
            return InstalledApp(
                bundleID: fallback.bundleID,
                name: fallback.displayName,
                version: "",
                containerPath: dir,
                icon: nil
            )
        }
    }

    static func inferredApp(
        for fallback: InstalledApp,
        knownAppsByBundleID: [String: InstalledApp],
        launchServicesIdentifiers: Set<String>
    ) -> InstalledApp? {
        guard UUID(uuidString: fallback.bundleID) != nil else { return fallback }
        if let metadata = readContainerMetadata(containerPath: fallback.containerPath) {
            let bundleID = metadata.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            if ContainerBundleCandidateResolver.isValidBundleIdentifier(bundleID), !bundleID.hasPrefix("systemgroup.") {
                let info = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
                let resolvedName = metadata.displayName.isEmpty ? (info["name"] as? String ?? bundleID) : metadata.displayName
                return InstalledApp(bundleID: bundleID, name: resolvedName, version: info["version"] as? String ?? "", containerPath: fallback.containerPath, icon: info["icon"] as? UIImage)
            }
        }
        let handle = grantContainerAccess(fallback.containerPath)
        defer { if handle >= 0 { releaseContainerAccess(handle) } }
        let libraryPath = (fallback.containerPath as NSString).appendingPathComponent("Library")
        let savedStatePath = (libraryPath as NSString).appendingPathComponent("Saved Application State")
        let preferencesPath = (libraryPath as NSString).appendingPathComponent("Preferences")
        let savedStates = (try? FileManager.default.contentsOfDirectory(atPath: savedStatePath)) ?? []
        let preferences = (try? FileManager.default.contentsOfDirectory(atPath: preferencesPath)) ?? []
        let strongCandidates = ContainerBundleCandidateResolver.candidates(savedStateNames: savedStates, preferenceFileNames: [])
        let candidates = ContainerBundleCandidateResolver.candidates(savedStateNames: savedStates, preferenceFileNames: preferences)
        func resolvedApp(from candidates: [String], source: String) -> InstalledApp? {
            for bundleID in candidates {
                if let known = knownAppsByBundleID[bundleID] {
                    return InstalledApp(bundleID: bundleID, name: known.name, version: known.version, containerPath: fallback.containerPath, icon: known.icon)
                }
                let info = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
                guard info["found"] as? Bool == true else { continue }
                return InstalledApp(bundleID: bundleID, name: info["name"] as? String ?? bundleID, version: info["version"] as? String ?? "", containerPath: fallback.containerPath, icon: info["icon"] as? UIImage)
            }
            guard let bundleID = ContainerBundleCandidateResolver.confirmedCandidate(candidates: candidates, launchServicesIdentifiers: launchServicesIdentifiers) else { return nil }
            return InstalledApp(bundleID: bundleID, name: bundleID, version: "", containerPath: fallback.containerPath, icon: nil)
        }
        if let app = resolvedApp(from: candidates, source: "state/preferences") { return app }
        if let bundleID = strongCandidates.first {
            return InstalledApp(bundleID: bundleID, name: bundleID, version: "", containerPath: fallback.containerPath, icon: nil)
        }
        let artifactPaths = [
            (libraryPath as NSString).appendingPathComponent("SplashBoard/Snapshots"),
            (libraryPath as NSString).appendingPathComponent("Caches/Snapshots"),
            (libraryPath as NSString).appendingPathComponent("Cookies"),
            (libraryPath as NSString).appendingPathComponent("WebKit")
        ]
        let artifactNames = artifactPaths.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
        let artifactCandidates = ContainerBundleCandidateResolver.candidates(savedStateNames: [], preferenceFileNames: [], artifactNames: artifactNames)
        if let app = resolvedApp(from: artifactCandidates, source: "artifacts") { return app }
        return nil
    }

    static func inferUnidentifiedApps(
        in apps: [InstalledApp],
        knownApps: [InstalledApp],
        launchServicesIdentifiers: Set<String> = []
    ) -> [InstalledApp] {
        let knownByBundleID = Dictionary(knownApps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        return apps.map { app in
            guard UUID(uuidString: app.bundleID) != nil,
                  let inferred = autoreleasepool(invoking: {
                      inferredApp(for: app, knownAppsByBundleID: knownByBundleID, launchServicesIdentifiers: launchServicesIdentifiers)
                  }) else { return app }
            return inferred
        }
    }

    // Fix lỗi trả về [FileEntry]
    static func listFiles(in directory: String) -> [FileEntry] {
        return listFiles(at: directory)
    }

    static func listFiles(at path: String) -> [FileEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [FileEntry] = []
        for item in items {
            if item.hasPrefix(".") { continue }
            let full = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let attributes = try? fm.attributesOfItem(atPath: full)
            let size = isDir.boolValue ? -1 : (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            entries.append(FileEntry(
    name: item,
    path: full,
    isDirectory: isDir.boolValue,
    size: size,
    modificationDate: attributes?[.modificationDate] as? Date
))
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func readTextFile(at path: String, limit: Int = 200_000) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "Unable to read file." }
        let truncated = data.prefix(limit)
        if let text = String(data: truncated, encoding: .utf8) { return data.count > limit ? text + "\n… [truncated]" : text }
        if let text = String(data: truncated, encoding: .utf16) { return data.count > limit ? text + "\n… [truncated]" : text }
        return "Binary data (\(data.count) bytes) -- not text."
    }
}