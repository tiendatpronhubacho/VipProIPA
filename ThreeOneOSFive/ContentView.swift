import SwiftUI
import UIKit
import AVFoundation

// MARK: - CẤU HÌNH TABBAR CHO MỌI IOS (CHỐNG LỖI XÁM)
func configureTabBarAppearance() {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor.black
    
    let itemAppearance = UITabBarItemAppearance()
    itemAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.5)
    itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.5)]
    itemAppearance.selected.iconColor = UIColor(AppTheme.accent)
    itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.accent)]
    
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

// MARK: - MAIN CONTENT VIEW (TAB NAVIGATION)
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @StateObject private var patchStore = PatchProjectStore()
    
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(patchStore: patchStore)
                .tabItem {
                    Label("Trang chủ", systemImage: "house.fill")
                }
                .tag(0)
            
            FeaturesView(patchStore: patchStore)
                .tabItem {
                    Label("Chức năng", systemImage: "cube.fill")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .accentColor(AppTheme.accent)
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
            
            // Background Image
            GeometryReader { proxy in
                loadImageFromBundle(named: "background_home")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            
            // Lớp phủ đen
            Color.black.opacity(0.3).ignoresSafeArea()

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
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer()
        }
    }

    private var devicePanel: some View {
        VStack(spacing: 0) {
            panelTitle("DEVICE STATUS", icon: "shield.lefthalf.filled")
            statusRow(icon: "apple.logo", title: "iOS", value: AppInfo.osVersion, color: AppTheme.secondaryAccent)
            statusRow(icon: "iphone", title: "Device", value: AppInfo.displayMachineName, color: AppTheme.secondaryAccent)
            statusRow(icon: "checkmark.seal.fill", title: "Support", value: appState.isSupported ? "SUPPORTED" : "UNSUPPORTED", color: appState.isSupported ? .green : .red)
        }
        .padding(16)
        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.accent.opacity(0.4), lineWidth: 0.5))
    }

    private var gameLaunchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelTitle("LAUNCH GAME", icon: "arrow.up.forward.app.fill")
            HStack(spacing: 12) {
                launchButton(title: "FF VN", subtitle: "Free Fire VN", color: AppTheme.accent, scheme: "freefirevn")
                lockedLaunchButton(title: "FF MAX", subtitle: "Locked • Coming Soon", color: AppTheme.secondaryAccent)
            }
            Button {
                showCleaner = true
            } label: {
                Label("Clean Cache & Temp", systemImage: "trash.slash.fill")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.accent.opacity(0.5), lineWidth: 0.5))
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
                .foregroundStyle(AppTheme.accent.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.65), in: Capsule())
        .overlay(Capsule().stroke(AppTheme.accent.opacity(0.3), lineWidth: 0.5))
    }

    private var developerCredits: some View {
        VStack(spacing: 10) {
            Text("Developed by TienDat")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            Text("Zalo TienDat")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.85))
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
                .background(AppTheme.accent.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.accent.opacity(0.42), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func panelTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(AppTheme.accent)
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
            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func lockedLaunchButton(title: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color.opacity(0.72))
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Text(subtitle)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.72))
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.3), lineWidth: 0.5))
        .opacity(0.72)
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
    @State private var patchOperationBusy = false
    @State private var patchMessage = "READY -- SELECT A PATCH"
    @State private var selectedMenu = 0 // 0: AIM, 1: MOD
    @State private var debugMessage = ""

    @State private var p1 = false; @State private var p2 = false; @State private var p3 = false
    @State private var p4 = false; @State private var p5 = false; @State private var p6 = false
    @State private var p7 = false; @State private var p8 = false; @State private var p9 = false
    @State private var p10 = false; @State private var p11 = false; @State private var p12 = false
    @State private var p13 = false; @State private var p14 = false 
private func normalize(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "+", with: "")
        .replacingOccurrences(of: ".3105", with: "")
        .replacingOccurrences(of: ".3106", with: "")
}
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
            .overlay(Color.black.opacity(0.65))

            VStack(spacing: 16) {
                // Custom Tab Bar (AIM / MOD)
                HStack(spacing: 0) {
                    menuTabButton(title: "AIM", icon: "scope", index: 0)
                    menuTabButton(title: "MOD", icon: "cube.box.fill", index: 1)
                }
                .padding(4)
                .background(Color.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.accent.opacity(0.5), lineWidth: 0.5))
                .padding(.horizontal, 18)
                .padding(.top, 18)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if selectedMenu == 0 {
                            // TAB AIM
                            patchRow(name: "Aim Drag", target: "FREE FIRE • VN", package: "Aim Drag.3105", state: $p1)
                            patchRow(name: "Aim Neck", target: "FREE FIRE • VN", package: "Aim Neck.3105", state: $p2)
                            patchRow(name: "Aim Body", target: "FREE FIRE • VN", package: "Aim Body.3105", state: $p3)
                            patchRow(name: "Nhe Tam", target: "FREE FIRE • VN", package: "Nhe Tam.3105", state: $p4)
                            patchRow(name: "Aim Chest", target: "FREE FIRE • VN", package: "Aim Chest.3105", state: $p5)
                            patchRow(name: "Aim R8", target: "FREE FIRE • VN", package: "Aim R8.3105", state: $p6)
                            patchRow(name: "Aim Magic", target: "FREE FIRE • VN", package: "Aim Magic.3105", state: $p7)
                            patchRow(name: "Neck Anten", target: "FREE FIRE • VN", package: "Neck Anten.3105", state: $p8)
                            patchRow(name: "Nhe Anten", target: "FREE FIRE • VN", package: "Nhe Anten.3105", state: $p9)
                        } else {
                            // TAB MOD
                            patchRow(name: "Mod Sonic", target: "FREE FIRE • DIMITRI", package: "Mod Sonic Dimitri.3105", state: $p10)
                            patchRow(name: "Mod Thỏ", target: "FREE FIRE • DIMITRI", package: "Mod Thỏ Dimitri.3105", state: $p11)
                            patchRow(name: "Mod Roblox", target: "FREE FIRE • DIMITRI", package: "Mod Roblox Dimitri.3105", state: $p12)
                            patchRow(name: "Mod Báo Hồng", target: "FREE FIRE • DIMITRI", package: "Mod Báo Hồng Dimitri.3105", state: $p13)
                            patchRow(name: "Mod Baki", target: "FREE FIRE • ALOCK", package: "Mod Baki Alock.3105", state: $p14)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }

                // Thanh trạng thái dưới cùng
                HStack(spacing: 8) {
                    Circle().fill(patchMessage.localizedCaseInsensitiveContains("successful") ? .green : AppTheme.accent).frame(width: 7, height: 7)
                    Text(patchOperationBusy ? "PROCESSING PATCH…" : patchMessage)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.7), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.accent.opacity(0.4), lineWidth: 0.5))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
        }
                        .onAppear {
            patchStore.reload()
            syncPatchStates()
            
            // Dùng appState từ Environment thay vì tạo mới
            if !appState.exploitStatus.isSuccess {
                appState.runKernelExploitIfNeeded()
            }
            
            if let error = UserDefaults.standard.string(forKey: "debug_bootstrap_error") {
                self.debugMessage = error
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, !patchOperationBusy else { return }
            syncPatchStates()
            patchMessage = "READY -- SELECT A PATCH"
        }
    }

    // Nút chuyển Tab (AIM/MOD)
    private func menuTabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMenu = index
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(selectedMenu == index ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedMenu == index ? AppTheme.accent.opacity(0.8) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // Hàng Patch (Đã thay Toggle bằng Button)
    private func patchRow(name: String, target: String, package: String, state: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(target)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryAccent)
            }
            
            Spacer()
            
            // Nút bấm giả lập Toggle
            Button {
                guard !patchOperationBusy else { return }
                let newValue = !state.wrappedValue
                state.wrappedValue = newValue
                togglePatch(packageFilename: package, state: state, isEnabling: newValue)
            } label: {
                ZStack {
                    Capsule()
                        .fill(state.wrappedValue ? AppTheme.accent : Color.white.opacity(0.15))
                        .frame(width: 50, height: 30)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .offset(x: state.wrappedValue ? 10 : -10)
                        .shadow(radius: 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(patchOperationBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.accent.opacity(0.3), lineWidth: 0.5))
        .opacity(patchOperationBusy ? 0.5 : 1)
    }

    private func syncPatchStates() {
        p1 = isPatchActive("Aim Drag.3105"); p2 = isPatchActive("Aim Neck.3105")
        p3 = isPatchActive("Aim Body.3105"); p4 = isPatchActive("Nhẹ Tâm.3105")
        p5 = isPatchActive("Aim Chest.3105"); p6 = isPatchActive("Aim R8.3105")
        p7 = isPatchActive("Aim Magic.3105"); p8 = isPatchActive("Neck+Anten.3105")
        p9 = isPatchActive("Nhẹ + Anten.3105"); p10 = isPatchActive("Mod Sonic Dimitri.3105")
        p11 = isPatchActive("Mod Thỏ Dimitri.3105"); p12 = isPatchActive("Mod Roblox Dimitri.3105")
        p13 = isPatchActive("Mod Báo Hồng Dimitri.3105"); p14 = isPatchActive("Mod Baki Alock.3105")
    }

    private func isPatchActive(_ packageFilename: String) -> Bool {
        let target = normalize(packageFilename)
        return patchStore.items.first(where: {
            normalize($0.packageURL.lastPathComponent) == target
        }).flatMap { DevicePatchService.latestReceipt(projectID: $0.id) } != nil
    }

    private func setPatchState(for packageFilename: String, enabled: Bool) {
        switch packageFilename {
        case "Aim Drag.3105": p1 = enabled
        case "Aim Neck.3105": p2 = enabled
        case "Aim Body.3105": p3 = enabled
        case "Nhẹ Tâm.3105": p4 = enabled
        case "Aim Chest.3105": p5 = enabled
        case "Aim R8.3105": p6 = enabled
        case "Aim Magic.3105": p7 = enabled
        case "Neck+Anten.3105": p8 = enabled
        case "Nhẹ + Anten.3105": p9 = enabled
        case "Mod Sonic Dimitri.3105": p10 = enabled
        case "Mod Thỏ Dimitri.3105": p11 = enabled
        case "Mod Roblox Dimitri.3105": p12 = enabled
        case "Mod Báo Hồng Dimitri.3105": p13 = enabled
        case "Mod Baki Alock.3105": p14 = enabled
        default: break
        }
    }

    private func togglePatch(packageFilename: String, state: Binding<Bool>, isEnabling: Bool) {
        guard !patchOperationBusy else { return }
        
        let target = normalize(packageFilename)
        guard let item = patchStore.items.first(where: {
            normalize($0.packageURL.lastPathComponent) == target
        }) else {
            patchMessage = "ERROR -- PACKAGE NOT FOUND (\(patchStore.items.count) items loaded)"
            state.wrappedValue = !isEnabling // Revert
            return
        }

        patchOperationBusy = true
        patchMessage = "PROCESSING -- \(packageFilename)"
        let project = item.project
        let projectID = item.id

        DispatchQueue.global(qos: .userInitiated).async {
            var resultMessage = ""
            
            do {
                if !isEnabling {
                    // Đang tắt (Restore)
                    guard let receipt = DevicePatchService.latestReceipt(projectID: projectID) else {
                        DispatchQueue.main.async {
                            self.setPatchState(for: packageFilename, enabled: false)
                            self.patchMessage = "OFF -- NO ACTIVE PATCH FOUND"
                            self.patchOperationBusy = false
                        }
                        return
                    }
                    try DevicePatchService.restore(receipt: receipt)
                    resultMessage = "Restore Successful -- \(packageFilename)"
                } else {
                    // Đang bật (Apply)
                    guard let project else {
                        DispatchQueue.main.async {
                            self.patchStore.requestUnlock(for: item)
                            self.patchMessage = "PASSWORD REQUIRED -- ENTER PACKAGE PASSWORD"
                            self.setPatchState(for: packageFilename, enabled: false)
                            self.patchOperationBusy = false
                        }
                        return
                    }
                    _ = try DevicePatchService.apply(project: project)
                    resultMessage = "Inject Successful -- \(packageFilename)"
                }
            } catch {
                resultMessage = "FAILED -- \(String(describing: error))"
                DispatchQueue.main.async {
                    self.setPatchState(for: packageFilename, enabled: !isEnabling)
                }
            }

            DispatchQueue.main.async {
                if resultMessage.contains("Successful") {
                    self.patchMessage = resultMessage
                    if isEnabling { PatchAudioFeedback.bypassActivated() } else { PatchAudioFeedback.originalRestored() }
                } else {
                    self.patchMessage = resultMessage
                }
                self.patchOperationBusy = false
            }
        }
    }
}

// MARK: - HELPER VIEWS & COMPONENTS
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