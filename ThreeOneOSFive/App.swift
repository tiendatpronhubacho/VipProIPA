import SwiftUI
import UIKit

@main
struct ThreeOneOSSixApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var licenseManager = LicenseManager()
    
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        log("app: TienDat \(appVersion) (\(appBuild)) launching -- iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
        SandboxAccess.prepare()
        PatchProjectLibrary.bootstrap()
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasCompletedSetup {
                    SetupView()
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity)
                } else if licenseManager.isActive {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(patchDraftCoordinator)
                        .environmentObject(fileOperationCoordinator)
                        .environmentObject(patchStore)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity)
                } else {
                    LicenseActivationView(manager: licenseManager)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: hasCompletedSetup)
            .animation(.easeInOut(duration: 0.3), value: licenseManager.isActive)
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: true)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version) + "\n" + language.text("update.current", AppInfo.appVersion)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onAppear {
                if licenseManager.isActive {
                    appState.detectSupport()
                    checkForUpdate()
                }
            }
            .onChange(of: licenseManager.isActive) { active in
                if active {
                    appState.detectSupport()
                    checkForUpdate()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, licenseManager.isActive else { return }
                appState.detectSupport()
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: SandboxAccess.backend.displayName)
                    log("app: existing \(SandboxAccess.backend.displayName) access is still active")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        let backend = SandboxAccess.backend
        log("app: running \(backend.displayName) access setup on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: backend.displayName)
                    if backend == .kernel {
                        log("app: kernel access active")
                    } else {
                        log("app: \(backend.displayName) access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: backend.displayName, code: -1)
                    if backend == .worseQuery && !SandboxAccess.hasAppGroup {
                        log("app: worse_query needs an App Group; re-sign with a tool that provides one")
                    } else {
                        log("app: \(backend.displayName) setup failed -- relaunch the app before retrying")
                    }
                }
            }
        }
    }
}