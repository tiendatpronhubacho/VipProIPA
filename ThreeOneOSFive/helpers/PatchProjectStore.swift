import Foundation

struct PatchStoreAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let messageKey: String
    var messageArgument: String?

    init(titleKey: String, messageKey: String, messageArgument: String? = nil) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.messageArgument = messageArgument
    }

    func message(language: AppLanguage) -> String {
        if let messageArgument {
            return language.text(messageKey, messageArgument)
        }
        return language.text(messageKey)
    }
}

@MainActor
final class PatchProjectStore: ObservableObject {
    @Published private(set) var items: [PatchLibraryItem] = []
    @Published private(set) var isBusy = false
    @Published private(set) var loadIssues: [String] = []
    @Published var passwordRequest: PatchPasswordRequest?
    @Published var alert: PatchStoreAlert?
    @Published var unlockErrorKey: String?
    
    @Published var activePatchIDs: Set<UUID> = [] {
        didSet {
            let ids = activePatchIDs.map { $0.uuidString }
            UserDefaults.standard.set(ids, forKey: "com.tiendat.develop.activePatchIDs")
        }
    }

    private struct PendingUnlock {
        let data: Data
        let summary: PatchPackageSummary
        let existingURL: URL?
        let origin: PatchPackageOrigin?
    }

    private var pendingUnlock: PendingUnlock?
    private let receiptKeyPrefix = "com.tiendat.develop.receipt."

    init() {
        if let saved = UserDefaults.standard.array(forKey: "com.tiendat.develop.activePatchIDs") as? [String] {
            self.activePatchIDs = Set(saved.compactMap { UUID(uuidString: $0) })
        }
        isBusy = true
        PatchProjectLibrary.bootstrap()
        Task { @MainActor in
            await downloadPatchesFromGithub()
            self.items = PatchProjectLibrary.load()
            self.updateLoadIssues()
            self.isBusy = false
        }
    }

    private var remotePackageNames: [String] {
        [
            "Aim Drag.3105", "Aim Neck.3105", "Aim Body.3105",
            "Nhe Tam.3105", "Aim Chest.3105", "Aim R8.3105",
            "Aim Magic.3105", "Neck Anten.3105", "Nhe Anten.3105",
            "Mod Sonic Dimitri.3105", "Mod Thỏ Dimitri.3105", "Mod Roblox Dimitri.3105",
            "Mod Báo Hồng Dimitri.3105", "Mod Baki Alock.3105"
        ]
    }

    private func downloadPatchesFromGithub() async {
        let fm = FileManager.default
        guard let rootURL = try? PatchProjectLibrary.packageRootURL() else {
            loadIssues = ["Không tạo được thư mục Application Support/PatchProjects"]
            return
        }
        let baseURL = "https://raw.githubusercontent.com/tiendatpronhubacho/VipProIPA/main/Patches/"
        var failures: [String] = []
        for filename in remotePackageNames {
            let destination = rootURL.appendingPathComponent(filename)
            if fm.fileExists(atPath: destination.path),
               let existing = try? Data(contentsOf: destination),
               (try? PatchPackageCodec.inspect(existing)) != nil { continue }
            try? fm.removeItem(at: destination)
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
            guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: allowed),
                  let url = URL(string: baseURL + encoded) else {
                failures.append("\(filename): URL không hợp lệ")
                continue
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw NSError(domain: "PatchDownload", code: status,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
                }
                _ = try PatchPackageCodec.inspect(data)
                try data.write(to: destination, options: .atomic)
                log("patch: downloaded and validated \(filename)")
            } catch {
                failures.append("\(filename): \(error.localizedDescription)")
                log("patch: download/validation failed -- \(filename): \(error)")
            }
        }
        loadIssues = failures
    }

    private func updateLoadIssues() {
        let loaded = Set(items.map { $0.packageURL.lastPathComponent })
        let absent = remotePackageNames.filter { !loaded.contains($0) }
        if !absent.isEmpty {
            let existing = Set(loadIssues)
            loadIssues.append(contentsOf: absent.filter { name in
                !existing.contains(where: { $0.hasPrefix(name + ":") })
            }.map { "\($0): gói không có hoặc không giải mã được" })
        }
        loadIssues = Array(Set(loadIssues)).sorted()
    }

    func reload() {
        PatchProjectLibrary.bootstrap()
        items = PatchProjectLibrary.load()
        updateLoadIssues()
    }

    // MARK: - Apply & Restore

    func applyPatch(_ item: PatchLibraryItem) {
        guard !isBusy else { return }
        guard let project = item.project else {
            present(.invalidProject)
            return
        }
        
        isBusy = true
        let itemID = item.id
        
        Task { @MainActor [weak self] in
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try DevicePatchService.apply(project: project)
                }.value
                
                guard let self = self else { return }
                self.activePatchIDs.insert(itemID)
                self.isBusy = false
                self.alert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.applied_message")
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.isBusy = false
                self.present(error)
            } catch {
                guard let self = self else { return }
                self.isBusy = false
                self.present(.applyFailed)
            }
        }
    }

    func restorePatch(_ item: PatchLibraryItem) {
        guard !isBusy else { return }
        let itemID = item.id
        
        guard let receipt = DevicePatchService.latestReceipt(projectID: itemID) else {
            activePatchIDs.remove(itemID)
            return
        }
        
        isBusy = true
        
        Task { @MainActor [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try DevicePatchService.restore(receipt: receipt)
                }.value
                
                guard let self = self else { return }
                self.activePatchIDs.remove(itemID)
                self.isBusy = false
                self.alert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.restored_message")
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.isBusy = false
                self.present(error)
            } catch {
                guard let self = self else { return }
                self.isBusy = false
                self.present(.restoreFailed)
            }
        }
    }

    // MARK: - CRUD
    func create(project: PatchProject, password: String?) {
        runOperation(successMessageKey: "patch.created_message") {
            let encoded = try PatchPackageCodec.encodeNew(project: project, password: password)
            let summary = try PatchPackageCodec.inspect(encoded.data)
            let workspace = try PatchWorkspaceService.createWorkspace(for: project)
            var savedURL: URL?
            do {
                if summary.isPasswordProtected {
                    try PatchKeyStore.store(encoded.contentKey, for: summary)
                }
                savedURL = try PatchProjectLibrary.save(
                    data: encoded.data,
                    projectName: project.name
                )
                try PatchProjectLibrary.markAsAuthorCopy(packageID: project.id)
            } catch {
                try? FileManager.default.removeItem(at: workspace)
                if let savedURL {
                    try? FileManager.default.removeItem(at: savedURL)
                }
                try? PatchKeyStore.delete(for: summary)
                throw error
            }
        }
    }

    func update(project: PatchProject) {
        guard let item = items.first(where: { $0.id == project.id }),
              let contentKey = item.contentKey else {
            present(.invalidProject)
            return
        }
        runOperation(successMessageKey: "patch.updated_message") {
            let original = try PatchProjectLibrary.readPackage(at: item.packageURL)
            let updated = try PatchPackageCodec.update(
                original,
                project: project,
                contentKey: contentKey,
                schemaVersion: PatchPackageCodec.latestSchemaVersion
            )
            _ = try PatchProjectLibrary.save(
                data: updated,
                projectName: project.name,
                existingURL: item.packageURL
            )
        }
    }

    func importPackage(at sourceURL: URL) {
        guard !isBusy else { return }
        isBusy = true
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        
        Task { @MainActor [weak self] in
            defer {
                if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try PatchProjectLibrary.readPackage(at: sourceURL)
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = self?.existingPackageURL(for: summary.packageID)
                
                let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL
                )
                
                guard let self = self else { return }
                if let pending {
                    self.requestPassword(pending: pending)
                } else {
                    self.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.failOperation(error)
            } catch {
                guard let self = self else { return }
                self.failOperation(.unsupportedFormat)
            }
        }
    }

    @discardableResult
    func importPackage(
        data: Data,
        password: String? = nil,
        origin: PatchPackageOrigin? = nil
    ) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        
        Task { @MainActor [weak self] in
            do {
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = self?.existingPackageURL(for: summary.packageID)
                
                let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL,
                    password: password,
                    origin: origin
                )
                
                guard let self = self else { return }
                if let pending {
                    self.requestPassword(pending: pending)
                } else {
                    self.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.failOperation(error)
            } catch {
                guard let self = self else { return }
                self.failOperation(.unsupportedFormat)
            }
        }
        return true
    }

    func presentImportError(_ error: PatchPackageError) {
        present(error)
    }

    func importPackage(from source: PatchImportSource) {
        switch source {
        case .file(let url): importPackage(at: url)
        case .remote(let url): importPackage(fromRemoteURL: url)
        case .invalid: present(.invalidImportLink)
        }
    }

    private func importPackage(fromRemoteURL remoteURL: URL) {
        guard !isBusy, PatchImportRoute.validatedRemoteURL(remoteURL) != nil else {
            if !isBusy { present(.invalidImportLink) }
            return
        }
        isBusy = true
        
        Task { @MainActor [weak self] in
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 600
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }

                let (temporaryURL, response) = try await session.download(from: remoteURL)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let finalURL = response.url,
                      PatchImportRoute.validatedRemoteURL(finalURL) != nil else {
                    throw PatchPackageError.remoteImportFailed
                }

                let data = try PatchProjectLibrary.readPackage(at: temporaryURL)
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = self?.existingPackageURL(for: summary.packageID)
                
                let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL
                )
                
                guard let self = self else { return }
                if let pending {
                    self.requestPassword(pending: pending)
                } else {
                    self.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.failOperation(error)
            } catch {
                guard let self = self else { return }
                self.failOperation(.remoteImportFailed)
            }
        }
    }

    func requestUnlock(for item: PatchLibraryItem) {
        guard item.isLocked, !isBusy else { return }
        do {
            let data = try PatchProjectLibrary.readPackage(at: item.packageURL)
            pendingUnlock = PendingUnlock(
                data: data,
                summary: item.summary,
                existingURL: item.packageURL,
                origin: item.origin
            )
            passwordRequest = PatchPasswordRequest(
                summary: item.summary,
                origin: item.origin
            )
        } catch let error as PatchPackageError {
            present(error)
        } catch {
            present(.unsupportedFormat)
        }
    }

    func unlock(password: String) {
        guard let pending = pendingUnlock, !isBusy else { return }
        isBusy = true
        unlockErrorKey = nil
        
        Task { @MainActor [weak self] in
            do {
                let decoded = try PatchPackageCodec.decode(pending.data, password: password)
                try PatchKeyStore.store(decoded.contentKey, for: pending.summary)
                do {
                    try PatchProjectLibrary.installImportedPackage(
                        data: pending.data,
                        decoded: decoded,
                        summary: pending.summary,
                        existingURL: pending.existingURL,
                        origin: pending.origin
                    )
                } catch {
                    try? PatchKeyStore.delete(for: pending.summary)
                    throw error
                }
                
                guard let self = self else { return }
                self.clearPendingUnlock()
                self.finishOperation(successMessageKey: "patch.unlocked_message")
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.failUnlock(error)
            } catch {
                guard let self = self else { return }
                self.failUnlock(.invalidPasswordOrCorruptedPackage)
            }
        }
    }

    func cancelUnlock() {
        clearPendingUnlock()
        isBusy = false
    }

    func clearUnlockError() {
        unlockErrorKey = nil
    }

    func delete(_ item: PatchLibraryItem) {
        do {
            try PatchProjectLibrary.delete(item)
            reload()
        } catch let error as PatchPackageError {
            present(error)
        } catch {
            present(.invalidProject)
        }
    }

    func synchronizeWorkspace(projectID: UUID, reportsSuccess: Bool = false) {
        guard let item = items.first(where: { $0.id == projectID }),
              item.summary.schemaVersion >= 2,
              !isBusy else { return }
        isBusy = true
        
        Task { @MainActor [weak self] in
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try PatchProjectLibrary.synchronizeWorkspace(item: item)
                }.value
                guard let self = self else { return }
                self.finishWorkspaceSynchronization(reportsSuccess: reportsSuccess)
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.failOperation(error)
            } catch {
                guard let self = self else { return }
                self.failOperation(.invalidProject)
            }
        }
    }

    private func finishWorkspaceSynchronization(reportsSuccess: Bool) {
        reload()
        isBusy = false
        if reportsSuccess {
            alert = PatchStoreAlert(
                titleKey: "common.done",
                messageKey: "patch.workspace_synced_message"
            )
        }
    }

    private func runOperation(
        successMessageKey: String,
        operation: @escaping () throws -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        
        Task { @MainActor [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try operation()
                }.value
                guard let self = self else { return }
                self.finishOperation(successMessageKey: successMessageKey)
            } catch let error as PatchPackageError {
                guard let self = self else { return }
                self.failOperation(error)
            } catch {
                guard let self = self else { return }
                self.failOperation(.invalidProject)
            }
        }
    }

    private func requestPassword(pending: PendingUnlock) {
        pendingUnlock = pending
        passwordRequest = PatchPasswordRequest(
            summary: pending.summary,
            origin: pending.origin
        )
        isBusy = false
    }

    private func existingPackageURL(for packageID: UUID) -> URL? {
        items.first(where: { $0.id == packageID })?.packageURL
    }

    private nonisolated static func persistImportedPackage(
        data: Data,
        summary: PatchPackageSummary,
        existingURL: URL?,
        password: String? = nil,
        origin: PatchPackageOrigin? = nil
    ) throws -> PendingUnlock? {
        if let key = try PatchKeyStore.load(for: summary) {
            let decoded = try PatchPackageCodec.decode(data, contentKey: key)
            try PatchProjectLibrary.installImportedPackage(
                data: data,
                decoded: decoded,
                summary: summary,
                existingURL: existingURL,
                origin: origin
            )
            return nil
        }
        if summary.isPasswordProtected {
            guard let password else {
                return PendingUnlock(
                    data: data,
                    summary: summary,
                    existingURL: existingURL,
                    origin: origin
                )
            }
            let decoded = try PatchPackageCodec.decode(data, password: password)
            try PatchKeyStore.store(decoded.contentKey, for: summary)
            do {
                try PatchProjectLibrary.installImportedPackage(
                    data: data,
                    decoded: decoded,
                    summary: summary,
                    existingURL: existingURL,
                    origin: origin
                )
            } catch {
                try? PatchKeyStore.delete(for: summary)
                throw error
            }
            return nil
        }
        let decoded = try PatchPackageCodec.decode(data, password: nil)
        try PatchProjectLibrary.installImportedPackage(
            data: data,
            decoded: decoded,
            summary: summary,
            existingURL: existingURL,
            origin: origin
        )
        return nil
    }

    private func clearPendingUnlock() {
        pendingUnlock = nil
        passwordRequest = nil
        unlockErrorKey = nil
    }

    private func finishOperation(successMessageKey: String) {
        reload()
        isBusy = false
        alert = PatchStoreAlert(titleKey: "common.done", messageKey: successMessageKey)
    }

    private func failOperation(_ error: PatchPackageError) {
        isBusy = false
        present(error)
    }

    private func failUnlock(_ error: PatchPackageError) {
        isBusy = false
        if case .invalidPasswordOrCorruptedPackage = error {
            unlockErrorKey = "patch.error.wrong_password"
        } else {
            unlockErrorKey = error.localizationKey
        }
    }

    private func present(_ error: PatchPackageError) {
        alert = PatchStoreAlert(
            titleKey: "common.failed",
            messageKey: error.localizationKey,
            messageArgument: error.localizationArgument
        )
    }
}