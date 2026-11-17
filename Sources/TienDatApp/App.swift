import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator();
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        log("app: TienDat launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
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
            Group {
                if licenseManager.isActive {
                    ContentView()
                        .environmentObject(licenseManager)
                } else {
                    LicenseActivationView(manager: licenseManager)
                }
            }
                .environmentObject(appState)
                .environmentObject(patchDraftCoordinator)
                .environmentObject(patchStore)
                .environmentObject(repositoryStore)
                .environmentObject(fileOperationCoordinator)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onAppear {
                licenseManager.beginLaunchSession()
                appState.detectSupport()
                checkForUpdate()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                licenseManager.beginLaunchSession()
                appState.detectSupport()
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
            .preferredColorScheme(.dark)
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String? = nil
    @Published var kernelExploitRunning = false

    /// This build intentionally ships without kernel exploit or sandbox escape.
    /// OS-version compatibility must never be presented as runtime access.
    var kernelExploitApplicable: Bool { false }
    var isSupported: Bool { false }
    var supportStatusLabel: String { "LIMITED — SANDBOX ACCESS DISABLED" }

    func detectSupport() {
        // The TienDat build keeps ordinary app features available but never
        // does not attempt kernel exploitation or sandbox escape. The patch
        // workflow therefore cannot claim target-container access is available.
        exploitStatus = .notStarted
        unsupportedMessage = "This safe build has no sandbox access. App-container patching is unavailable."
        kernelExploitRunning = false
    }

    func runKernelExploitIfNeeded() {
        log("TienDat: system-level exploit features are disabled in this build")
    }
}
