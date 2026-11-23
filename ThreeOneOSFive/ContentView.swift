import SwiftUI
import UIKit
import AVFoundation

// MARK: - QUẢN LÝ NHẠC NỀN
class AudioManager: ObservableObject {
    static let shared = AudioManager()
    private var player: AVAudioPlayer?
    
    @Published var isPlaying: Bool = UserDefaults.standard.bool(forKey: "background_music_enabled") {
        didSet {
            UserDefaults.standard.set(isPlaying, forKey: "background_music_enabled")
            if isPlaying { play() } else { stop() }
        }
    }
    
    init() {
        if isPlaying { play() }
    }
    
    func play() {
        guard let url = Bundle.main.url(forResource: "background_music", withExtension: "mp3") else {
            print("Không tìm thấy file nhạc background_music.mp3")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.play()
        } catch {
            print("Lỗi phát nhạc: \(error)")
        }
    }
    
    func stop() {
        player?.stop()
    }
}

// MARK: - CẤU HÌNH TABBAR (MÀU TỐI)
func configureTabBarAppearance() {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor.black
    
    let itemAppearance = UITabBarItemAppearance()
    itemAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.5)
    itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.5)]
    itemAppearance.selected.iconColor = UIColor.white
    itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
    
    appearance.stackedLayoutAppearance = itemAppearance
    appearance.inlineLayoutAppearance = itemAppearance
    appearance.compactInlineLayoutAppearance = itemAppearance
    
    UITabBar.appearance().standardAppearance = appearance
    if #available(iOS 15.0, *) {
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - HÀM LOAD ẢNH
func loadImageFromBundle(named name: String) -> Image {
    if let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
       let uiImage = UIImage(contentsOfFile: url.path) {
        return Image(uiImage: uiImage)
    }
    if let url = Bundle.main.url(forResource: name, withExtension: "JPG"),
       let uiImage = UIImage(contentsOfFile: url.path) {
        return Image(uiImage: uiImage)
    }
    if let uiImage = UIImage(named: name) {
        return Image(uiImage: uiImage)
    }
    return Image(systemName: "photo")
}

// MARK: - MAIN CONTENT VIEW
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @StateObject private var patchStore = PatchProjectStore()
    
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(patchStore: patchStore)
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }
                .tag(0)
            
            FeaturesView(patchStore: patchStore)
                .tabItem { Label("Chức năng", systemImage: "cube.fill") }
                .tag(1)
            
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .accentColor(.white)
        .preferredColorScheme(.dark)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.black, for: .tabBar)
        .onAppear {
            configureTabBarAppearance()
        }
        .sheet(item: $patchStore.passwordRequest, onDismiss: patchStore.cancelUnlock) { _ in
            PatchUnlockPrompt(store: patchStore)
        }
    }
}

// MARK: - TRANG CHỦ (HOME VIEW)
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var patchStore: PatchProjectStore
    @State private var showCleaner = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                loadImageFromBundle(named: "background_home")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            
            Color.black.opacity(0.2).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    brandHeader
                    devicePanel
                    gameLaunchPanel
                    footerStatus
                    developerCredits
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showCleaner) {
            CleanerView()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TIENDAT")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)
                Text("PATCH CONTROL CENTER")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
    }

    private var devicePanel: some View {
        VStack(spacing: 0) {
            panelTitle("DEVICE STATUS", icon: "shield.lefthalf.filled")
            statusRow(icon: "apple.logo", title: "iOS", value: AppInfo.osVersion, color: .white)
            statusRow(icon: "iphone", title: "Device", value: AppInfo.displayMachineName, color: .white)
            statusRow(icon: "checkmark.seal.fill", title: "Support", value: appState.isSupported ? "SUPPORTED" : "UNSUPPORTED", color: appState.isSupported ? .green : .red)
        }
        .padding(16)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }

    private var gameLaunchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelTitle("LAUNCH GAME", icon: "arrow.up.forward.app.fill")
            HStack(spacing: 12) {
                launchButton(title: "Free Fire VN", subtitle: "com.garena.ffvn", color: .white, scheme: "freefirevn")
            }
            Button {
                showCleaner = true
            } label: {
                Label("Clean Cache & Temp", systemImage: "trash.slash.fill")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var footerStatus: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 9, height: 9).shadow(color: .green, radius: 6)
            Text("SISTEMA PRONTO")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text("TIENDAT • PRONTO")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }

    private var developerCredits: some View {
        VStack(spacing: 10) {
            Text("Developed by TienDat")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            Text("Zalo TienDat")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 10) {
                channelButton(title: "Zalo", url: "https://zalo.me/0986321175")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func channelButton(title: String, url: String) -> some View {
        Button {
            guard let destination = URL(string: url) else { return }
            UIApplication.shared.open(destination)
        } label: {
            Label(title, systemImage: "paperplane.fill")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func panelTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white)
    }

    private func statusRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(color).frame(width: 24)
            Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text(value).font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(.white)
        }
        .padding(.top, 14)
    }

    private func launchButton(title: String, subtitle: String, color: Color, scheme: String) -> some View {
        Button { openGame(scheme: scheme) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func openGame(scheme: String) {
        guard let url = URL(string: "\(scheme)://") else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            print("launch: \(scheme) success=\(success)")
        }
    }
}

// MARK: - TRANG CHỨC NĂNG (FEATURES VIEW)
struct FeaturesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var patchStore: PatchProjectStore
    @EnvironmentObject private var appState: AppState
    
    @State private var currentScreen = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                loadImageFromBundle(named: "background_features")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.4))

            VStack(spacing: 0) {
                if currentScreen > 0 {
                    HStack {
                        Button {
                            withAnimation { currentScreen -= 1 }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text(currentScreen == 1 ? "Chức năng" : "Menu")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        }
                        Spacer()
                        Text(currentScreen == 1 ? "Free Fire VN" : (currentScreen == 2 ? "AIM" : "MOD"))
                            .font(.headline).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.left").opacity(0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if currentScreen == 0 {
                            mainAppSelection
                        } else if currentScreen == 1 {
                            menuSelection
                        } else if currentScreen == 2 {
                            patchList(isAim: true)
                        } else if currentScreen == 3 {
                            patchList(isAim: false)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
            }
        }
        // === THÊM 2 ĐOẠN NÀY ===
        .alert(item: $patchStore.alert) { alert in
            Alert(
                title: Text(alert.titleKey == "common.done" ? "Thành công" : "Lỗi"),
                message: Text(alert.message(language: .vietnamese)), // hoặc dùng AppLanguage hiện tại của bạn
                dismissButton: .default(Text("OK")) {
                    patchStore.alert = nil
                }
            )
        }
        .onChange(of: patchStore.isBusy) { busy in
            // optional: có thể thêm haptic hoặc log
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
        }
    }

    private var mainAppSelection: some View {
        VStack(spacing: 16) {
            Button { withAnimation { currentScreen = 1 } } label: {
                HStack {
                    Image(systemName: "flame.fill").font(.title2).foregroundStyle(.white)
                    VStack(alignment: .leading) {
                        Text("Free Fire VN").font(.headline).foregroundStyle(.white)
                        Text("com.garena.ffvn").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5))
                }
                .padding()
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var menuSelection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                menuButton(title: "AIM", icon: "scope", action: { withAnimation { currentScreen = 2 } })
                menuButton(title: "MOD", icon: "puzzlepiece.extension", action: { withAnimation { currentScreen = 3 } })
            }
        }
    }

    private func menuButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.white)
                Text(title).font(.headline).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func patchList(isAim: Bool) -> some View {
        VStack(spacing: 10) {
            if isAim {
                patchRow(name: "Aim Drag", target: "FREE FIRE • VN", package: "Aim Drag.3105")
                patchRow(name: "Aim Neck", target: "FREE FIRE • VN", package: "Aim Neck.3105")
                patchRow(name: "Aim Body", target: "FREE FIRE • VN", package: "Aim Body.3105")
                patchRow(name: "Nhe Tam", target: "FREE FIRE • VN", package: "Nhe Tam.3105")
                patchRow(name: "Aim Chest", target: "FREE FIRE • VN", package: "Aim Chest.3105")
                patchRow(name: "Aim R8", target: "FREE FIRE • VN", package: "Aim R8.3105")
                patchRow(name: "Aim Magic", target: "FREE FIRE • VN", package: "Aim Magic.3105")
                patchRow(name: "Neck Anten", target: "FREE FIRE • VN", package: "Neck Anten.3105")
                patchRow(name: "Nhe Anten", target: "FREE FIRE • VN", package: "Nhe Anten.3105")
            } else {
                patchRow(name: "Mod Sonic", target: "FREE FIRE • DIMITRI", package: "Mod Sonic Dimitri.3105")
                patchRow(name: "Mod Thỏ", target: "FREE FIRE • DIMITRI", package: "Mod Thỏ Dimitri.3105")
                patchRow(name: "Mod Roblox", target: "FREE FIRE • DIMITRI", package: "Mod Roblox Dimitri.3105")
                patchRow(name: "Mod Báo Hồng", target: "FREE FIRE • DIMITRI", package: "Mod Báo Hồng Dimitri.3105")
                patchRow(name: "Mod Baki", target: "FREE FIRE • ALOCK", package: "Mod Baki Alock.3105")
            }
            
            HStack(spacing: 8) {
    Circle()
        .fill(patchStore.isBusy ? .orange : (patchStore.activePatchIDs.isEmpty ? .white.opacity(0.5) : .green))
        .frame(width: 7, height: 7)
    
    Text(patchStore.isBusy ? "PROCESSING PATCH…" : (patchStore.activePatchIDs.isEmpty ? "READY -- SELECT A PATCH" : "PATCH APPLIED"))
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.85))
}
.padding(.horizontal, 14)
.padding(.vertical, 12)
.background(Color.white.opacity(0.1), in: Capsule())
.overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
.padding(.top, 10)
        }
    }

    private func patchRow(name: String, target: String, package: String) -> some View {
        let item = patchStore.items.first(where: { $0.packageURL.lastPathComponent.caseInsensitiveCompare(package) == .orderedSame })
        let isEnabled = item.flatMap { patchStore.activePatchIDs.contains($0.id) } ?? false
        
        return HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text(target).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                if item == nil {
                    Text("Thiếu gói patch — kiểm tra mạng / Sandbox Diagnostics")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
            
            Spacer()
            
            Button {
                guard let item = item, !patchStore.isBusy else { return }
                if isEnabled {
                    patchStore.restorePatch(item)
                } else {
                    patchStore.applyPatch(item)
                }
            } label: {
                ZStack {
                    Capsule().fill(isEnabled ? Color.white : Color.white.opacity(0.2)).frame(width: 50, height: 30)
                    Circle().fill(isEnabled ? Color.black : Color.white).frame(width: 24, height: 24)
                        .offset(x: isEnabled ? 10 : -10).shadow(radius: 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(patchStore.isBusy || item == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        .opacity(patchStore.isBusy ? 0.5 : 1)
    }
}

// MARK: - CÀI ĐẶT (SETTINGS VIEW)
struct SettingsView: View {
    @ObservedObject private var audioManager = AudioManager.shared
    @State private var showSandboxDiagnostics = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                loadImageFromBundle(named: "background_settings")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.5))
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    HStack(spacing: 16) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                        
                        VStack(alignment: .leading) {
                            Text("TienDat IPA").font(.title3.bold()).foregroundStyle(.white)
                            Text("Phiên bản 2.0").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding(.top, 20)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ÂM THANH").font(.caption).foregroundStyle(.white.opacity(0.5))
                        HStack {
                            Text("Nhạc Nền").foregroundStyle(.white)
                            Spacer()
                            Toggle("", isOn: $audioManager.isPlaying).tint(.white)
                        }
                        .padding()
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GIAO DIỆN").font(.caption).foregroundStyle(.white.opacity(0.5))
                        HStack(spacing: 0) {
                            Text("Sáng").frame(maxWidth: .infinity).padding(.vertical, 10)
                            Text("Tối").frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.white.opacity(0.2)).cornerRadius(8)
                            Text("Theo hệ thống").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CHẨN ĐOÁN SANDBOX").font(.caption).foregroundStyle(.white.opacity(0.5))
                        Button { showSandboxDiagnostics = true } label: {
                            HStack {
                                Image(systemName: "stethoscope").foregroundStyle(.white)
                                Text("Sandbox Diagnostics").foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.6))
                            }
                            .padding()
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("THIẾT BỊ").font(.caption).foregroundStyle(.white.opacity(0.5))
                        VStack(spacing: 0) {
                            HStack {
                                Text("Model phần cứng").foregroundStyle(.white)
                                Spacer()
                                Text(AppInfo.displayMachineName).foregroundStyle(.white.opacity(0.7))
                            }
                            .padding()
                            Divider().background(Color.white.opacity(0.2))
                            HStack {
                                Text("Phiên bản iOS").foregroundStyle(.white)
                                Spacer()
                                Text(AppInfo.osVersion).foregroundStyle(.white.opacity(0.7))
                            }
                            .padding()
                        }
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showSandboxDiagnostics) {
            NavigationStack { SandboxDiagnosticsView() }
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - HELPER VIEWS
struct AnimatedHyperBackdrop: View {
    @State private var animate = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.pageBackground
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: animate ? 120 : -120, y: -proxy.size.height * 0.23)
                Circle()
                    .fill(AppTheme.secondaryAccent.opacity(0.08))
                    .frame(width: 260, height: 260)
                    .blur(radius: 80)
                    .offset(x: animate ? -100 : 100, y: proxy.size.height * 0.22)
                GridOverlay()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { animate = true }
            }
        }
    }
}

private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 44
            stride(from: CGFloat(0), through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat(0), through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(AppTheme.accent.opacity(0.055)), lineWidth: 1)
        }
    }
}

enum PatchAudioFeedback {
    private static let synthesizer = AVSpeechSynthesizer()
    static func bypassActivated() { speak("Bypass ativado") }
    static func originalRestored() { speak("Bypass desativado") }
    private static func speak(_ message: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: message)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        utterance.voice = voices.first(where: {
            ($0.language.hasPrefix("pt-BR") || $0.language.hasPrefix("pt-PT") || $0.language.hasPrefix("pt")) && $0.gender == .female && $0.quality == .enhanced
        }) ?? voices.first(where: {
            $0.language.hasPrefix("pt-BR") || $0.language.hasPrefix("pt-PT") || $0.language.hasPrefix("pt")
        }) ?? AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = 0.43
        utterance.pitchMultiplier = 1.10
        utterance.volume = 0.90
        synthesizer.speak(utterance)
    }
}

struct PatchUnlockPrompt: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Package password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in store.clearUnlockError() }
                    if let errorKey = store.unlockErrorKey {
                        Text(AppLanguage.english.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Enter the password once to unlock this TienDat package on this device.")
                }
            }
            .navigationTitle("Unlock package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock", action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

// MARK: - SETUP VIEW
struct SetupView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var step = 1
    
    @State private var isPaired = false
    @State private var isVPNConnected = false
    @State private var isChecking = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    Capsule().fill(Color.white).frame(height: 4)
                    Capsule().fill(step == 2 ? Color.white : Color.gray.opacity(0.3)).frame(height: 4)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
                Text(step == 1 ? "Thiết lập lần đầu • Bước 1/2" : "Thiết lập lần đầu • Bước 2/2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                if step == 1 {
                    pairStep
                } else {
                    vpnStep
                }
                
                Spacer()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
    
    private var pairStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .padding()
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            
            Text("Thiết lập Pairing")
                .font(.title2.bold())
            
            Text("Trên iOS 26.6.2 trở lên, hãy hoàn tất pairing bằng công cụ Apple trên máy tính trước khi tiếp tục. Ứng dụng này không tự tạo Pairing PIN.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "iphone.gen3").foregroundStyle(.white)
                    VStack(alignment: .leading) {
                        Text("Pair trực tiếp trên máy").font(.headline)
                        Text(isPaired ? "Thiết bị: 3105 (Đã pair)" : "Cần hoàn tất pairing để tiếp tục")
                            .font(.caption).foregroundStyle(isPaired ? .green : .gray)
                    }
                    Spacer()
                    if isPaired { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                .padding()
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                
                if !isPaired {
                    Button(action: confirmPairingCompleted) {
                        Text("Xác nhận đã hoàn tất Pairing").font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding().background(Color.white, in: Capsule())
                    }
                } else {
                    Button(action: { step = 2 }) {
                        Text("Tiếp tục bước 2").font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding().background(Color.white, in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var vpnStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40)).foregroundStyle(.white)
                .padding().background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            
            Text("Chuẩn bị kết nối AirLift").font(.title2.bold())
            
            Text("Cài LocalDevVPN, bật VPN trong Cài đặt > VPN và kết nối Wi-Fi. Sau đó xác nhận để tiếp tục; iOS không cho ứng dụng này đọc trạng thái VPN của ứng dụng khác.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "wifi").foregroundStyle(.green)
                    Text("Kết nối Wi-Fi").font(.headline)
                    Spacer()
                    Text("Đang sử dụng Wi-Fi").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .padding()
                Divider()
                HStack {
                    Image(systemName: "network").foregroundStyle(.white)
                    VStack(alignment: .leading) {
                        Text("LocalDevVPN").font(.headline)
                        Text(isVPNConnected ? "VPN đã bật" : "Cần bật LocalDevVPN để tiếp tục").font(.caption).foregroundStyle(isVPNConnected ? .green : .gray)
                    }
                    Spacer()
                    Image(systemName: isVPNConnected ? "checkmark.circle.fill" : "circle").foregroundStyle(isVPNConnected ? .green : .gray)
                }
                .padding()
            }
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            Button(action: { UIApplication.shared.open(URL(string: "https://apps.apple.com/vn/app/localdevvpn/id6755608044?l=vi")!) }) {
                HStack {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Tải LocalDevVPN từ App Store")
                }
                .font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding().background(Color.white.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal)
            
            Button(action: checkVPNConnection) {
                if isChecking {
                    ProgressView().tint(.black).font(.headline).frame(maxWidth: .infinity).padding().background(Color.white, in: Capsule())
                } else {
                    Text("Tôi đã bật LocalDevVPN – Tiếp tục").font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding().background(Color.white, in: Capsule())
                }
            }
            .padding(.horizontal).disabled(isChecking)
            
            // Chỉ cho bỏ qua trên các phiên bản thấp hơn iOS 26.6.1.
            if isBelowIOS2661 {
                Button(action: { hasCompletedSetup = true }) {
                    Text("Bỏ qua (iOS dưới 26.6.1)")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 10)
                }
            }
        }
    }
    
    // iOS does not expose a public API for checking another app's VPN tunnel.
    // Ask the user to confirm LocalDevVPN is enabled instead of rejecting a valid VPN.
    private func checkVPNConnection() {
        let alert = UIAlertController(
            title: "Xác nhận LocalDevVPN",
            message: "iOS không cho ứng dụng này kiểm tra trạng thái VPN do ứng dụng khác cài đặt. Hãy bật LocalDevVPN trong Cài đặt > VPN, sau đó chọn Tiếp tục.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Chưa bật", style: .cancel))
        alert.addAction(UIAlertAction(title: "Đã bật – Tiếp tục", style: .default) { _ in
            self.isVPNConnected = true
            self.hasCompletedSetup = true
        })

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }

    private var isBelowIOS2661: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.majorVersion < 26 { return true }
        if v.majorVersion > 26 { return false }
        if v.minorVersion < 6 { return true }
        if v.minorVersion > 6 { return false }
        return v.patchVersion < 1
    }

    // Pairing must be performed by an Apple-supported pairing tool.
    // This confirmation records the user's acknowledgement; it does not create a pairing.
    private func confirmPairingCompleted() {
        let alert = UIAlertController(
            title: "Xác nhận Pairing",
            message: "Hãy chỉ tiếp tục nếu bạn đã hoàn tất pairing thiết bị bằng công cụ Apple trên máy tính. Ứng dụng không thể tự tạo Pairing PIN hoặc xác minh pairing qua API công khai.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Chưa hoàn tất", style: .cancel))
        alert.addAction(UIAlertAction(title: "Đã hoàn tất", style: .default) { _ in
            self.isPaired = true
            self.step = 2
        })

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }
}
