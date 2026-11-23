
import SwiftUI
import UIKit

struct SandboxDiagnosticsView: View {
    @State private var probeRunning = false
    @State private var probeResult: Bool?
    @State private var copied = false
    @State private var resetRunning = false
    @State private var resetSummary: String?
    @State private var refreshID = 0

    var body: some View {
        List {
            Section {
                LabeledContent("iOS", value: AppInfo.osVersion)
                LabeledContent("Build", value: AppInfo.osBuild)
                LabeledContent("Thiết bị", value: AppInfo.displayMachineName)
                LabeledContent("Backend", value: SandboxAccess.backend.displayName)
                LabeledContent("App Group", value: SandboxAccess.appGroup ?? "Không có entitlement")
                LabeledContent(
                    "Probe",
                    value: probeResult.map { $0 ? "OK" : "THẤT BẠI" } ?? "Chưa chạy"
                )

                Button {
                    runProbe()
                } label: {
                    if probeRunning {
                        ProgressView("Đang kiểm tra…")
                    } else {
                        Label("Kiểm tra quyền sandbox", systemImage: "stethoscope")
                    }
                }
                .disabled(probeRunning)
            } header: {
                Text("Thiết bị và backend")
            }

            Section {
                Button(role: .destructive) {
                    runReset()
                } label: {
                    if resetRunning {
                        ProgressView("Đang reset…")
                    } else {
                        Label(
                            "Reset Access Cache và kiểm tra lại",
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                }
                .disabled(resetRunning)

                if let resetSummary {
                    Text(resetSummary)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Reset cache truy cập")
            } footer: {
                Text("Chỉ dùng khi worse_query báo lỗi cache. Thao tác này không xóa dữ liệu ứng dụng.")
            }

            Section {
                if SandboxDiagnostics.recentGrants.isEmpty {
                    Text("Chưa có lần cấp quyền nào được ghi nhận.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(SandboxDiagnostics.recentGrants.reversed()) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.at, style: .time)
                                    .font(.caption.monospaced())

                                Spacer()

                                Text(record.code >= 0 ? "OK" : "FAIL \(record.code)")
                                    .font(.caption.bold())
                                    .foregroundStyle(
                                        record.code >= 0 ? .green : .red
                                    )
                            }

                            Text("Backend: \(record.backend)")
                                .font(.caption)

                            Text(record.path)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            } header: {
                Text("Lỗi grant gần đây")
            }

            Section {
                Button {
                    UIPasteboard.general.string =
                        SandboxDiagnostics.exportText(probeResult: probeResult)
                    copied = true
                } label: {
                    Label(
                        copied ? "Đã sao chép báo cáo" : "Sao chép báo cáo chẩn đoán",
                        systemImage: copied ? "checkmark.circle" : "doc.on.doc"
                    )
                }

                Button("Xóa lịch sử lỗi trên màn hình", role: .destructive) {
                    SandboxDiagnostics.reset()
                    refreshID += 1
                }
            }
        }
        .id(refreshID)
        .navigationTitle("Sandbox Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runProbe() {
        probeRunning = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = SandboxAccess.probe()

            DispatchQueue.main.async {
                probeResult = result
                probeRunning = false
                refreshID += 1
            }
        }
    }

    private func runReset() {
        resetRunning = true
        resetSummary = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let ok = worse_query_reset_access_cache()
            SandboxAccess.invalidateProbeCache()
            let result = SandboxAccess.probe()

            DispatchQueue.main.async {
                resetSummary = ok
                    ? "Đã reset cache. Probe: \(result ? "OK" : "THẤT BẠI")"
                    : "Reset cache thất bại."

                probeResult = result
                resetRunning = false
                refreshID += 1
            }
        }
    }
}
