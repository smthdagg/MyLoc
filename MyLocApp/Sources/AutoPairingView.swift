import SwiftUI
import UniformTypeIdentifiers
import MyLocCore

struct AutoPairingView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPairingImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("当前状态") {
                    HStack {
                        Label(
                            viewModel.hasPairing ? "配对记录已就绪" : "尚未导入配对记录",
                            systemImage: viewModel.hasPairing ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .foregroundStyle(viewModel.hasPairing ? .green : .orange)
                    }
                    if let summary = viewModel.pairingSummary {
                        LabeledContent("设备", value: summary.deviceName)
                        LabeledContent("指纹", value: summary.fingerprint)
                    }
                    HStack {
                        Label(
                            viewModel.tunnelReachable ? "LocalDevVPN 隧道已连通" : "LocalDevVPN 隧道未连通",
                            systemImage: viewModel.tunnelReachable ? "checkmark.shield.fill" : "exclamationmark.shield"
                        )
                        .foregroundStyle(viewModel.tunnelReachable ? .green : .orange)
                        Spacer()
                        Button("检测") {
                            Task { _ = await viewModel.checkTunnel() }
                        }
                    }
                    if !viewModel.tunnelReachable {
                        Button {
                            viewModel.openLocalDevVPN()
                        } label: {
                            Label("打开 LocalDevVPN 建立隧道", systemImage: "arrow.up.forward.app")
                        }
                    }
                }

                Section("从文件导入配对记录（推荐）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 将 iPhone 用 USB 线连接电脑，解锁并点击“信任”。")
                        Text("2. 在电脑上运行 idevice_pair 或本项目提供的 export_pairing 工具，生成本机专属的 .mobiledevicepairing 文件。")
                        Text("3. 将文件传到 iPhone“文件” App（AirDrop / 微信 / iCloud），点击下方按钮导入即可。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Button {
                        showPairingImporter = true
                    } label: {
                        Label(
                            viewModel.hasPairing ? "重新导入 .mobiledevicepairing 文件" : "选择 .mobiledevicepairing 文件导入",
                            systemImage: "doc.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section("安全说明") {
                    Text("• 配对文件一机一份，不可跨设备通用，但在本机可长期复用。\n• 导入后仅加密保存在本机 Keychain（WhenUnlockedThisDeviceOnly），不会上传或写入普通日志。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设备配对与隧道")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPairingImporter, allowedContentTypes: [.propertyList, .data]) { result in
                if case .success(let url) = result {
                    viewModel.importPairingFile(url: url)
                }
            }
            .task {
                _ = await viewModel.checkTunnel()
            }
        }
    }
}
