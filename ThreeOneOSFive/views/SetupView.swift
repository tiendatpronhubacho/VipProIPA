import SwiftUI
import NetworkExtension

struct SetupView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var step = 1
    
    @State private var isPaired = false
    @State private var pairingPIN = ""
    @State private var isVPNConnected = false
    @State private var isChecking = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Progress Bar
                HStack(spacing: 8) {
                    Capsule().fill(AppTheme.accent).frame(height: 4)
                    Capsule().fill(step == 2 ? AppTheme.accent : Color.gray.opacity(0.3)).frame(height: 4)
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
    
    // MARK: - BƯỚC 1: PAIRING
    private var pairStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            
            Text("Thiết lập Pairing")
                .font(.title2.bold())
            
            Text("iOS 26.6.2 trở lên có thể pair trực tiếp trên thiết bị. Hãy làm theo hướng dẫn và nhập mã PIN khi hệ thống yêu cầu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "iphone.gen3")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("Pair trực tiếp trên máy")
                            .font(.headline)
                        Text(isPaired ? "Thiết bị: 3105 (Đã pair)" : "Cần hoàn tất pairing để tiếp tục")
                            .font(.caption)
                            .foregroundStyle(isPaired ? .green : .gray)
                    }
                    Spacer()
                    if isPaired {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                
                if !isPaired {
                    Button(action: startPairing) {
                        Text("Pair trực tiếp trên iPhone")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange, in: Capsule())
                    }
                } else {
                    Button(action: { step = 2 }) {
                        Text("Tiếp tục bước 2")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange, in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - BƯỚC 2: LOCAL VPN
    private var vpnStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            
            Text("Chuẩn bị kết nối AirLift")
                .font(.title2.bold())
            
            Text("Cài LocalDevVPN, bật VPN và kết nối Wi-Fi. 3102 sẽ kiểm tra tunnel thật trước khi cho phép sử dụng.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
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
                    Image(systemName: "network").foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("LocalDevVPN").font(.headline)
                        Text(isVPNConnected ? "VPN đã bật" : "Cần bật LocalDevVPN để tiếp tục").font(.caption).foregroundStyle(isVPNConnected ? .green : .gray)
                    }
                    Spacer()
                    Image(systemName: isVPNConnected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isVPNConnected ? .green : .gray)
                }
                .padding()
            }
            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            Button(action: openVPNStore) {
                HStack {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Tải LocalDevVPN từ App Store")
                }
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal)
            
            Button(action: checkVPNConnection) {
                if isChecking {
                    ProgressView().tint(.white)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange, in: Capsule())
                } else {
                    Text("Kiểm tra kết nối AirLift")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange, in: Capsule())
                }
            }
            .padding(.horizontal)
            .disabled(isChecking)
        }
    }
    
    // MARK: - Logic (Cần gắn code Pairing và VPN thật từ App 3102)
    private func startPairing() {
        // TODO: Gọi hàm Pairing của 3102 (Tạo Pairing PIN)
        isPaired = true
    }
    
    private func openVPNStore() {
        if let url = URL(string: "https://apps.apple.com/app/id6447500368") { // Link ID ví dụ
            UIApplication.shared.open(url)
        }
    }
    
    private func checkVPNConnection() {
        isChecking = true
        NEVPNManager.shared().loadFromPreferences { error in
            DispatchQueue.main.async {
                isChecking = false
                if let connection = NEVPNManager.shared().connection {
                    isVPNConnected = (connection.status == .connected || connection.status == .connecting)
                    if isVPNConnected {
                        hasCompletedSetup = true
                    }
                } else {
                    isVPNConnected = false
                }
            }
        }
    }
}